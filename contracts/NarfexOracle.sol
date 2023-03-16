//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./PancakeLibrary.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title Oracle contract for Narfex Fiats and storage of commissions
/// @author Danil Sakhinov
/// @author Vladimir Smelov
/// @notice Fiat prices are regularly sent by the owner from the backend service
/// @notice Added bulk data acquisition functions
contract NarfexOracle is Ownable {
    using Address for address;
    using SignedMath for int;
    uint internal constant PERCENT_PRECISION = 10**4;  // 100% = 10**4

    struct Token {
        bool isFiat;
        bool isCustomCommission; // Use default commission on false
        bool isCustomReward; // Use default referral percent on false
        uint price; // USD price only for fiats
        uint priceUpdatedAtTimestamp;  // When the price was updated
        uint reward; // Referral percent only for fiats (used in Router) denominated by PERCENT_PRECISION
        int commission; // Commission percent with. Can be lower than zero  (used in Router) denominated by PERCENT_PRECISION
        uint transferFee; // Token transfer fee with 1000 decimals precision (20 for NRFX is 2%) (used in Router) denominated by PERCENT_PRECISION
    }

    /// Calculated Token data (for view method response)
    struct TokenData {
        bool isFiat;
        int commission;
        uint price;
        uint priceUpdatedAtTimestamp;
        uint reward;
        uint transferFee;
    }

    address[] internal fiats; // List of tracked fiat stablecoins
    address[] internal customCommissionTokens; // List of crypto tokens with different commission
    mapping (address => Token) public tokens;

    int defaultFiatCommission = 0; // Use as a commission if isCustomCommission = false for fiats
    int defaultTokenCommission = 0; // Use as a commission if isCustomCommission = false for customCommissionTokens
    uint defaultReward = 0; // Use as a default referral percent if isCustomReward = false

    address public updater; // Updater account. Has rights to update prices
    address immutable public USDC; // Main stablecoin address in the current network (we use USDC)

    event SetUpdater(address indexed updaterAddress);
    event PriceUpdated(
        address indexed token,
        uint256 indexed priceUpdatedAtTimestamp,
        uint price
    );
    event TokenRewardChanged(address indexed token, uint256 reward);
    event IsCustomRewardSet(address indexed token);
    event IsCustomRewardUnset(address indexed token);
    event DefaultSettingsSet(
        int defaultFiatCommission,
        int defaultTokenCommission,
        uint defaultReward
    );
    event TokenTransferFeeSet(address indexed token, uint256 fee);
    event TokenIsFiatSet(address indexed token);
    event TokenIsNotFiatSet(address indexed token);

    /// @notice only factory owner and router have full access
    modifier canUpdate {
        require(_msgSender() == owner() || _msgSender() == updater, "You have no access");
        _;
    }

    constructor(address _USDC) {
        USDC = _USDC;
    }

    /// @notice Returns ratio
    /// @notice this price maybe manipulated just before the request, it's not critical since it's used for front-end. Don't use it inside transactions!
    /// @notice this price is impacted by DEX fee (and does not include internal token fees), it's not critical since it's used for front-end. Don't use it inside transactions!
    function getPairRatio(address _token0, address _token1) internal view returns (uint) {
        IPancakePair pair = IPancakePair(PancakeLibrary.pairFor(_token0, _token1));
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        return pair.token0() == _token0
            ? PancakeLibrary.getAmountOut(10**IERC20Metadata(_token0).decimals(), reserve0, reserve1)
            : PancakeLibrary.getAmountOut(10**IERC20Metadata(_token1).decimals(), reserve1, reserve0);
    }

    /// @notice Returns token USD price
    /// @dev not every token has a pair for Token-USDC, a lot of tokens have only Token-ETH pair.
    function getDEXPrice(address _address) internal view returns (uint) {
        return _address == USDC
            ? 10**IERC20Metadata(USDC).decimals()
            : getPairRatio(_address, USDC);
    }

    /// @notice Returns token USD price for fiats and customCommissionTokens both
    /// @param _address Token address
    /// @return price USD price
    /// @return priceUpdatedAtTimestamp when the price was updated (now for no fiat tokens)
    function getPrice(address _address) public view returns (
        uint price,
        uint priceUpdatedAtTimestamp
    ) {
        Token storage token = tokens[_address];
        if (token.isFiat) {
            price = token.price;
            priceUpdatedAtTimestamp = token.priceUpdatedAtTimestamp;
        } else {
            price = getDEXPrice(_address);
            priceUpdatedAtTimestamp = block.timestamp;
        }
    }

    /// @notice Returns token USD price for many tokens
    /// @param _tokens Tokens addresses
    /// @return prices USD prices array with 18 digits of precision
    /// @return timestamps Prices update timestamps
    function getPrices(address[] calldata _tokens) public view returns (
        uint[] memory prices,
        uint[] memory timestamps
    ) {
        uint length = _tokens.length;
        prices = new uint[](length);
        timestamps = new uint[](length);
        unchecked {  // overflow is not possible
            for (uint i = 0; i < length; i++) {
                (prices[i], timestamps[i]) = getPrice(_tokens[i]);
            }
        }
        return (prices, timestamps);
    }

    /// @notice Returns address balances for many tokens
    /// @param _address Wallet address
    /// @param _tokens Tokens addresses
    /// @return Balances
    function getBalances(address _address, address[] calldata _tokens) public view returns (uint[] memory) {
        uint length = _tokens.length;
        uint[] memory response = new uint[](length);
        unchecked {  // overflow is not possible
            for (uint i = 0; i < length; i++) {
                response[i] = IERC20Metadata(_tokens[i]).balanceOf(_address);
            }
        }
        return response;
    }

    /// @notice Returns true if given token is Narfex Fiat
    /// @param _address Token address
    /// @return Token.isFiat value
    function getIsFiat(address _address) public view returns (bool) {
        return tokens[_address].isFiat;
    }

    /// @notice Returns token commission
    /// @param _address Token address
    /// @return Commission - multiplier with 1000 digits of precision
    function getCommission(address _address) public view returns (int) {
        Token storage token = tokens[_address];
        if (token.isCustomCommission) {
            return token.commission;
        } else {
            return token.isFiat
                ? defaultFiatCommission
                : defaultTokenCommission;
        }
    }

    /// @notice Returns token transfer fee
    /// @param _address Token address
    /// @return Fee with 1000 digits of precision
    function getTokenTransferFee(address _address) public view returns (uint) {
        return tokens[_address].transferFee;
    }

    /// @notice Returns fiat commission
    /// @param _address Token address
    /// @return Commission - multiplier with 1000 digits of precision
    function getReferralPercent(address _address) public view returns (uint) {
        Token storage token = tokens[_address];
        if (token.isFiat) {
            return token.isCustomReward
                ? token.reward
                : defaultReward;
        } else {
            return 0;
        }
    }

    /// @notice Returns array of Narfex Fiats addresses
    /// @return Array of fiats addresses
    function getFiats() public view returns (address[] memory) {
        return fiats;
    }

    /// @notice Returns array of customCommissionTokens addresses with different commissions
    /// @return Array of customCommissionTokens addresses
    function getCoins() public view returns (address[] memory) {
        return customCommissionTokens;
    }

    /// @notice Returns array of all known tokens to manage commissions
    /// @return Array of tokens addresses
    function getAllTokens() public view returns (address[] memory) {
        uint fiatsLength = fiats.length;
        uint coinsLength = customCommissionTokens.length;
        address[] memory responseTokens = new address[](fiatsLength + coinsLength);
        unchecked {  // overflow is not possible
            for (uint i = 0; i < fiatsLength; i++) {
                responseTokens[i] = fiats[i];
            }
            for (uint i = 0; i < coinsLength; i++) {
                responseTokens[fiatsLength + i] = customCommissionTokens[i];
            }
        }
        return responseTokens;
    }

    /// @notice Returns all commissions and rewards data
    /// @return defaultFiatCommission Default fiat commission
    /// @return defaultTokenCommission Default coin commission
    /// @return defaultReward Default referral reward percent
    /// @return responseTokens Array of Token structs
    function getSettings() public view returns (
        int,
        int,
        uint,
        Token[] memory
    ) {
        address[] memory allTokens = getAllTokens();
        uint length = allTokens.length;
        Token[] memory responseTokens = new Token[](length);
        unchecked {  // overflow is not possible
            for (uint i = 0; i < length; i++) {
                responseTokens[i] = tokens[allTokens[i]];
            }
        }

        return (
            defaultFiatCommission,
            defaultTokenCommission,
            defaultReward,
            responseTokens
        );
    }

    /// @notice Returns calculated Token data
    /// @param _address Token address
    /// @param _skipCoinPrice Allow to skip external calls for non-fiats
    /// @return tokenData Struct
    function getTokenData(address _address, bool _skipCoinPrice)
        public view returns (TokenData memory tokenData)
    {
        tokenData.isFiat = getIsFiat(_address);
        tokenData.commission = getCommission(_address);
        if (!tokenData.isFiat || _skipCoinPrice) {  //xx WARNING why do you have it for "!tokenData.isFiat"?
            (tokenData.price, tokenData.priceUpdatedAtTimestamp) = getPrice(_address);
        }
        tokenData.reward = getReferralPercent(_address);
        tokenData.transferFee = getTokenTransferFee(_address);
    }

    /// @notice Returns calculates Token data for many tokens
    /// @param _tokens Array of addresses
    /// @param _skipCoinPrice Allow to skip external calls for non-fiats
    /// @return Array of TokenData structs
    function getTokensData(address[] calldata _tokens, bool _skipCoinPrice)
        public view returns (TokenData[] memory)
    {
        TokenData[] memory response = new TokenData[](_tokens.length);
        unchecked {  // overflow is not possible
            for (uint i = 0; i < _tokens.length; i++) {
                response[i] = getTokenData(_tokens[i], _skipCoinPrice);
            }
        }
        return response;
    }

    /// @notice Set updater account address
    /// @param _updaterAddress Account address
    function setUpdater(address _updaterAddress) public onlyOwner {
        updater = _updaterAddress;
        emit SetUpdater(_updaterAddress);
    }

    /// @notice Update single fiat price
    /// @param _address Token address
    /// @param _priceUpdatedAtTimestamp The price timestamp
    /// @param _price Fiat price - unsigned number with 18 digits of precision  //xx MAJOR 91,248,263 why you say 18 decimals? USDC.decimals()==6, USDC.decimals()==6, for them the price will be PancakeLibrary.getAmountOut(10**IERC20(_token0).decimals(), reserve0, reserve1)==10**6
    /// @dev Only owner can manage prices
    function updatePrice(address _address, uint _priceUpdatedAtTimestamp, uint _price) public canUpdate {
        Token storage token = tokens[_address];
        require(block.timestamp >= _priceUpdatedAtTimestamp, "future timestamp");
        token.priceUpdatedAtTimestamp = _priceUpdatedAtTimestamp;
        token.price = _price;
        emit PriceUpdated({
            token: _address,
            priceUpdatedAtTimestamp: _priceUpdatedAtTimestamp,
            price: _price
        });
        if (!token.isFiat) {
            token.isFiat = true;  //xx LOW instead, it's safer to require(token.isFiat);
            fiats.push(_address);
            emit TokenIsFiatSet(_address);
        }
    }

    /// @notice Update many fiats prices
    /// @param _fiats Array of tokens addresses
    /// @param _prices Fiats prices array - unsigned numbers with 18 digits of precision
    /// @dev Only owner can manage prices
    function updatePrices(
        address[] calldata _fiats,
        uint[] calldata _pricesUpdatedAtTimestamps,
        uint[] calldata _prices
    ) public canUpdate {
        require (_fiats.length == _pricesUpdatedAtTimestamps.length, "Data lengths do not match");
        require (_fiats.length == _prices.length, "Data lengths do not match");
        unchecked {  // overflow is not possible
            for (uint i = 0; i < _fiats.length; i++) {
                updatePrice({
                    _address: _fiats[i],
                    _priceUpdatedAtTimestamp: _pricesUpdatedAtTimestamps[i],
                    _price: _prices[i]
                });
            }
        }
    }

    /// @notice Remove the fiat mark from the token
    /// @param _address Token address
    /// @dev Only owner can use it
    /// @dev Necessary for rare cases, if for some reason the token got into the fiats list
    function removeTokenFromFiats(address _address) public onlyOwner {
        Token storage token = tokens[_address];
        require(token.isFiat, "Token is not fiat");
        token.isFiat = false;
        emit TokenIsNotFiatSet(_address);
        unchecked {  // overflow is not possible
            for (uint i = 0; i < fiats.length; i++) {
                if (_address == fiats[i]) {
                    if (i != fiats.length-1) {
                        fiats[i] = fiats[fiats.length-1];
                    }
                    fiats.pop();
                    break;
                }
            }
        }
        token.price = 0;
    }

    /// @notice Remove the token from the customCommissionTokens list
    /// @param _address Token address
    /// @dev Only owner can use it
    function removeTokenFromCoins(address _address) public onlyOwner {
        unchecked {  // overflow is not possible
            for (uint i = 0; i < customCommissionTokens.length; i++) {
                if (_address == customCommissionTokens[i]) {
                    if (i != customCommissionTokens.length-1) {
                        customCommissionTokens[i] = customCommissionTokens[customCommissionTokens.length-1];
                    }
                    customCommissionTokens.pop();
                    break;
                }
            }
        }
    }

    /// @notice Set transfer fee percent for token
    /// @param _address Token address
    /// @param _fee Fee percent with 1000 decimals precision (20 = 2%)
    function setTokenTransferFee(address _address, uint _fee) public onlyOwner {
        Token storage token = tokens[_address];
        require(_fee < PERCENT_PRECISION, "too big fee");
        token.transferFee = _fee;
        emit TokenTransferFeeSet({token: _address, fee: _fee});
    }

    /// @notice Update default commissions and reward values
    /// @param _fiatCommission Default fiat commission
    /// @param _cryptoCommission Default coin commission
    /// @param _reward Default referral reward percent
    /// @dev Only owner can use it
    function updateDefaultSettings(  //xx WARNING 313-399 it looks like it should not be part of the oracle
        int _fiatCommission,
        int _cryptoCommission,
        uint _reward
    ) public onlyOwner {
        defaultFiatCommission = _fiatCommission;
        defaultTokenCommission = _cryptoCommission;
        defaultReward = _reward;
        emit DefaultSettingsSet({
            defaultFiatCommission: _fiatCommission,
            defaultTokenCommission: _cryptoCommission,
            defaultReward: _reward
        });
    }

    /// @notice Update tokens commissions
    /// @param tokensToCustom Array of tokens addresses which should stop using the default value
    /// @param tokensToDefault Array of tokens addresses which should start using the default value
    /// @param tokensChanged Array of tokens addresses that will receive changes
    /// @param newValues An array of commissions corresponding to an array of tokens
    /// @dev Only owner can use it
    function updateCommissions(
        address[] calldata tokensToCustom,
        address[] calldata tokensToDefault,
        address[] calldata tokensChanged,
        int[] calldata newValues
    ) public onlyOwner {
        unchecked {  // overflow is not possible
            require (tokensChanged.length == newValues.length, "Changed tokens length do not match values length");
            for (uint i = 0; i < tokensToCustom.length; i++) {
                Token storage token = tokens[tokensToCustom[i]];
                token.isCustomCommission = true;
                if (!token.isFiat) {
                    customCommissionTokens.push(tokensToCustom[i]);  //xx fiats ??
                }
            }
            for (uint i = 0; i < tokensToDefault.length; i++) {
                Token storage token = tokens[tokensToCustom[i]];
                token.isCustomCommission = false;
                if (!token.isFiat) {
                    removeTokenFromCoins(tokensToDefault[i]);
                }
            }
            for (uint i = 0; i < tokensChanged.length; i++) {
                require(newValues[i].abs() < PERCENT_PRECISION, "too big Commission");
                tokens[tokensToCustom[i]].commission = newValues[i];
            }
        }
    }

    /// @notice Update default values and tokens commissions by one request
    /// @param _defaultFiatCommission Default fiat commission
    /// @param _defaultCryptoCommission Default coin commission
    /// @param _defaultReward Default referral reward percent
    /// @param tokensToCustom Array of tokens addresses which should stop using the default value
    /// @param tokensToDefault Array of tokens addresses which should start using the default value
    /// @param tokensChanged Array of tokens addresses that will receive changes
    /// @param newValues An array of commissions corresponding to an array of tokens
    /// @dev Only owner can use it
    function updateAllCommissions(
        int _defaultFiatCommission,
        int _defaultCryptoCommission,
        uint _defaultReward,
        address[] calldata tokensToCustom,
        address[] calldata tokensToDefault,
        address[] calldata tokensChanged,
        int[] calldata newValues
    ) public onlyOwner {
        updateCommissions(tokensToCustom, tokensToDefault, tokensChanged, newValues);
        updateDefaultSettings(_defaultFiatCommission, _defaultCryptoCommission, _defaultReward);
    }

    /// @notice Update referral rewards percents for many fiats
    /// @param tokensToCustom Array of tokens addresses which should stop using the default value
    /// @param tokensToDefault Array of tokens addresses which should start using the default value
    /// @param tokensRewardChanged Array of tokens addresses that will receive changes
    /// @param newRewards An array of percents corresponding to an array of tokens
    /// @dev Only owner can use it
    function updateReferralPercents(
        address[] calldata tokensToCustom,
        address[] calldata tokensToDefault,
        address[] calldata tokensRewardChanged,
        uint[] calldata newRewards
    ) public onlyOwner {
        require (tokensRewardChanged.length == newRewards.length, "Changed tokens length do not match values length");
        unchecked {  // overflow is not possible
            for (uint i = 0; i < tokensToCustom.length; i++) {
                tokens[tokensToCustom[i]].isCustomReward = true;
                emit IsCustomRewardSet(tokensToCustom[i]);
            }
            for (uint i = 0; i < tokensToDefault.length; i++) {
                tokens[tokensToDefault[i]].isCustomReward = false;
                emit IsCustomRewardUnset(tokensToDefault[i]);
            }
            for (uint i = 0; i < tokensRewardChanged.length; i++) {
                require(newRewards[i] < PERCENT_PRECISION, "too big reward");
                tokens[tokensRewardChanged[i]].reward = newRewards[i];
                emit TokenRewardChanged(tokensRewardChanged[i], newRewards[i]);
            }
        }
    }

    // experimental: voting oracle
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet internal reporters;
    event ReporterAdded(address indexed account);
    event ReporterRemoved(address indexed account);
    struct TokenReport {
        uint256 timestamp;
        uint256 price;
    }
    mapping (address /*token*/ => mapping (address /*reporter*/ => TokenReport)) public tokenReporterReport;
    function addReporter(address account) external onlyOwner {
        require(reporters.add(account), "already in");
        emit ReporterAdded(account);
    }
    function removeReporter(address account) external onlyOwner {
        require(reporters.remove(account), "not in");
        emit ReporterRemoved(account);
    }
    function report(address token, uint256 timestamp, uint256 price) external {
        require(reporters.contains(msg.sender), "not reporter");
        require(timestamp <= block.timestamp, "from future");
        TokenReport storage _report = tokenReporterReport[token][msg.sender];
        require(timestamp > _report.timestamp, "not new");
        _report.timestamp = timestamp;
        _report.price = price;
    }
    function getPriceFromReporters(address token) external view returns(uint256) {
        uint256 minPrice = type(uint256).max;
        uint256 maxPrice = 0;
        uint256 pricesSum = 0;
        uint256 aliveReporters = 0;
        uint256 reportersLength = reporters.length();
        for (uint256 i = 0; i < reportersLength; i++) {
            TokenReport memory _report = tokenReporterReport[token][reporters.at(i)];
            if (block.timestamp - _report.timestamp > 5 minutes) continue;
            aliveReporters += 1;
            pricesSum += _report.price;
            if (_report.price > maxPrice) maxPrice = _report.price;
            if (_report.price < minPrice) minPrice = _report.price;
        }
        if (aliveReporters == 0) {
            return 0;
        } else {
            uint256 avgPrice = pricesSum / aliveReporters;  // better to use median
            require((avgPrice - minPrice) <= avgPrice / 100, "unstable price");
            require((maxPrice - avgPrice) <= avgPrice / 100, "unstable price");
            return avgPrice;
        }
    }
}