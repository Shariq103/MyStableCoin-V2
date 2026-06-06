// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MyStableCoin} from "./MyStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib, AggregatorV3Interface} from "./Library/OracleLib.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MSCEngine is ReentrancyGuard {
    /**
     * events
     */
    event CollateralDeposited(address indexed user, address indexed collateralToken, uint256 indexed amount);
    event CollateralRedeemed(address indexed user, address indexed collateralToken, uint256 indexed amount);

    /**
     * errors
     */
    error MSCEngine_TokenAndPriceFeedArrayLengthMismatch();
    error MSCEngine_AmountMustBeGreaterThanZero();
    error MSCEngine_AddressCannotBeZero();
    error MSCEngine_TransferFailed();
    error MSCEngine_BreaksHealthFactor(uint256 healthFactor);
    error MSCEngine_HealthFactorIsOk();
    error MSCEngine_HealthFactorIsNotImproved();
    error MSCEngine_NotEnoughCollateral();
    error MSCEngine_LiquidationAmountTooLow();

    /**
     * variables
     */
    using OracleLib for AggregatorV3Interface;

    MyStableCoin private immutable i_msc;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 50%
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // 1.0
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; // Chainlink has 8 decimals, we multiply by 1e10 to get 18 decimals
    uint256 private constant LIQUIDATION_BONUS = 10; // 10%
    uint256 private constant MIN_LIQUIDATION_AMOUNT = 1e18;

    mapping(address collateralToken => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_mscMinted;

    address[] private s_collateralTokens;

    /**
     * modifiers
     */
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert MSCEngine_AmountMustBeGreaterThanZero();
        }
        _;
    }

    modifier isAllowedToken(address collateralToken) {
        if (s_priceFeeds[collateralToken] == address(0)) {
            revert MSCEngine_AddressCannotBeZero();
        }
        _;
    }

    /**
     * constructor
     */
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address mscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert MSCEngine_TokenAndPriceFeedArrayLengthMismatch();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_msc = MyStableCoin(mscAddress);
    }

    /**
     * public functions
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;

        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert MSCEngine_TransferFailed();
        }
    }

    // Burn MSC
    function burnMsc(uint256 amountMscToBurn) public moreThanZero(amountMscToBurn) {
        s_mscMinted[msg.sender] -= amountMscToBurn;

        bool success = i_msc.transferFrom(msg.sender, address(this), amountMscToBurn);
        if (success == false) {
            revert MSCEngine_TransferFailed();
        }
        i_msc.burn(amountMscToBurn);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        if (success == false) {
            revert MSCEngine_TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // Mint MSC
    function mintMsc(uint256 amountMscToMint) public moreThanZero(amountMscToMint) nonReentrant {
        s_mscMinted[msg.sender] += amountMscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_msc.mint(msg.sender, amountMscToMint);
        if (minted == false) {
            revert MSCEngine_TransferFailed();
        }
    }

    /**
     * external functions
     */
    function depositCollateralAndMintMsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountMscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintMsc(amountMscToMint);
    }

    function redeemCollateralForMsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountMscToBurn)
        external
    {
        burnMsc(amountMscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function liquidate(address collateralToken, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        if (debtToCover < MIN_LIQUIDATION_AMOUNT) {
            revert MSCEngine_LiquidationAmountTooLow();
        }

        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert MSCEngine_HealthFactorIsOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralToken, debtToCover);
        uint256 totalCollateralToRedeem = (tokenAmountFromDebtCovered * (100 + LIQUIDATION_BONUS)) / 100;

        if (s_collateralDeposited[user][collateralToken] < totalCollateralToRedeem) {
            revert MSCEngine_NotEnoughCollateral();
        }

        s_collateralDeposited[user][collateralToken] -= totalCollateralToRedeem;
        bool success = IERC20(collateralToken).transfer(msg.sender, totalCollateralToRedeem);
        if (!success) {
            revert MSCEngine_TransferFailed();
        }

        s_mscMinted[user] -= debtToCover;
        bool done = i_msc.transferFrom(msg.sender, address(this), debtToCover);
        if (!done) {
            revert MSCEngine_TransferFailed();
        }
        i_msc.burn(debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingHealthFactor) {
            revert MSCEngine_HealthFactorIsNotImproved();
        }
    }

    /**
     * private / internal functions
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalCollateralValueInUsd, uint256 totalMscMinted)
    {
        totalCollateralValueInUsd = getAccountCollateralValue(user);
        totalMscMinted = s_mscMinted[user];

        return (totalCollateralValueInUsd, totalMscMinted);
    }

    function _calculateHealthFactor(uint256 totalCollateralValueInUsd, uint256 totalMscMinted)
        private
        pure
        returns (uint256 healthFactor)
    {
        if (totalMscMinted == 0) {
            return type(uint256).max; // If no MSC is minted, health factor is infinite (this is why we used " type(uint256).max " this cheatcode is used to represent the maximum value of uint256, which is 2^256 - 1. )
        }

        uint256 collateralAdjustedForThreshold;
        collateralAdjustedForThreshold = (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / 100;
        healthFactor = (collateralAdjustedForThreshold * PRECISION) / totalMscMinted;
        return healthFactor;
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalCollateralValueInUsd, uint256 totalMscMinted) = _getAccountInformation(user);
        return _calculateHealthFactor(totalCollateralValueInUsd, totalMscMinted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        (uint256 totalCollateralValueInUsd, uint256 totalMscMinted) = _getAccountInformation(user);
        uint256 userHealthFactor = _calculateHealthFactor(totalCollateralValueInUsd, totalMscMinted);

        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert MSCEngine_BreaksHealthFactor(userHealthFactor);
        }
    }

    function _normalizeToEighteenDecimals(address token, uint256 amount) private view returns (uint256 normalizedAmount) {
        uint8 decimals = IERC20Metadata(token).decimals();
        if (decimals < 18) {
            return amount * (10 ** (18 - decimals));
        }
        return amount;
    }

    /**
     * getter functions
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256 totalUsdValue) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        // This function returns 5 different pieces of data (roundId, answer, startedAt, updatedAt, answeredInRound).
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        amount = _normalizeToEighteenDecimals(token, amount);

        totalUsdValue = ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
        return totalUsdValue;
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            // s_collateralTokens[i];
            uint256 amountCollateral = s_collateralDeposited[user][s_collateralTokens[i]];
            totalCollateralValueInUsd += getUsdValue(s_collateralTokens[i], amountCollateral);
        }
        return totalCollateralValueInUsd;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256 tokenAmount) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        uint256 targetAmountInEighteenDecimals = (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
        uint8 decimals = IERC20Metadata(token).decimals();

        if (decimals < 18) {
            return targetAmountInEighteenDecimals / (10 ** (18 - decimals));
        }   
        return targetAmountInEighteenDecimals;
    }

    function getCollateralBalanceOfUser(address user, address collateralToken) external view returns (uint256) {
        return s_collateralDeposited[user][collateralToken];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralTokenPriceFeed(address collateralToken) external view returns (address) {
        return s_priceFeeds[collateralToken];
    }

    function getMscMinted(address user) external view returns (uint256) {
        return s_mscMinted[user];
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalCollateralValueInUsd, uint256 totalMscMinted)
    {
        return _getAccountInformation(user);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }
}
