//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./PancakeLibrary.sol";  //xx CRITICAL cannot compile the code since there is no such file in the repo
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IERC20 {  //xx LOW use import IERC20Metadata from OpenZeppelin
    function decimals() external view returns (uint8);  //xx WARNING not all erc20 tokens have it
    function balanceOf(address account) external view returns (uint256);
}

/// @title Oracle contract for Narfex Fiats and storage of commissions
/// @author Danil Sakhinov
/// @notice Fiat prices are regularly sent by the owner from the backend service
/// @notice Added bulk data acquisition functions
contract NarfexOracle is Ownable {
    using Address for address;

    struct Token {
        bool isFiat;
        bool isCustomCommission; // Use default commission on false
        bool isCustomReward; // Use defalt referral percent on false  //xx LOW typo in the word "default"
        uint price; // USD price only for fiats
        uint reward; // Referral percent only for fiats  //xx LOW where is it used?  //xx LOW 25-27 add postfix Numerator for clarity
        int commission; // Commission percent with. Can be lower than zero
        uint transferFee; // Token transfer fee with 1000 decimals precision (20 for NRFX is 2%)  //xx LOW 25-27 should it be part of the oracle? Maybe split it to another contract keeping the oracle as simply as possible and logically isolated.
    }

    /// Calculated Token data
    struct TokenData {
        bool isFiat;
        int commission;
        uint price;
        uint reward;
        uint transferFee;
    }

    address[] public fiats; // List of tracked fiat stablecoins  //xx LOW 39-40 OpenZeppelin enumerableSet
    address[] public coins; // List of crypto tokens with different commission  //xx LOW rename to tokensWithCustomCommission
    mapping (address => Token) public tokens;

    int defaultFiatCommission = 0; // Use as a commission if isCustomCommission = false for fiats
    int defaultCryptoCommission = 0; // Use as a commission if isCustomCommission = false for coins  //xx LOW wrong terminology https://www.bitstamp.net/learn/crypto-101/crypto-coins-vs-tokens/
    uint defaultReward = 0; // Use as a default referral percent if isCustomReward = false

    address public updater; // Updater account. Has rights for update prices  //xx LOW rephrase "to update"
    address public USDT; // Tether address in current network  //xx LOW "the current"  //xx LOW declare immutable  //xx WARNING it's here "Tether USDT", however on the call you told that we are gonna use "USDC", should we rename?

    event SetUpdater(address updaterAddress);  //xx LOW add events emitted on important settings set

    /// @notice only factory owner and router have full access
    modifier canUpdate {
        require(_msgSender() == owner() || _msgSender() == updater, "You have no access");
        _;
    }

    constructor(address _USDT) {
        USDT = _USDT;
    }

    // Returns ratio  //xx LOW 62,72 use NatSpec
    function getPairRatio(address _token0, address _token1) internal view returns (uint) {  //xx CRITICAL weak for price manipulations, consider the usage of uniswap v2 cumulative price oracle - https://docs.uniswap.org/contracts/v2/concepts/core-concepts/oracles
        IPancakePair pair = IPancakePair(PancakeLibrary.pairFor(_token0, _token1));
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        
        return pair.token0() == _token0  //xx MAJOR pancakeLibrary gives the price with fee, consider just using division of reserves
            ? PancakeLibrary.getAmountOut(10**IERC20(_token0).decimals(), reserve0, reserve1)
            : PancakeLibrary.getAmountOut(10**IERC20(_token1).decimals(), reserve1, reserve0);
    }

    // Returns token USD price
    function getDEXPrice(address _address) internal view returns (uint) {
        return _address == USDT
            ? 10**IERC20(USDT).decimals()
            : getPairRatio(_address, USDT);  //xx MAJOR not every token has a pair for Token-USDT, a lot of tokens have only Token-ETH pair. What should we do in this case? Should we take the price using the route Token-BNB BNB-USDT?
    }

    /// @notice Returns token USD price for fiats and coins both
    /// @param _address Token address
    /// @return USD price
    function getPrice(address _address) public view returns (uint) {
        Token storage token = tokens[_address];
        return token.isFiat
            ? token.price
            : getDEXPrice(_address);  //xx CRITICAL if backend goes offline, the oracle will give old prices. Consider returning the timestamp (or blocknumber) of the last price update, so the consumer will be able to understand if the prices are out-dated.
    }

    /// @notice Returns token USD price for many tokens
    /// @param _tokens Tokens addresses
    /// @return USD prices array with 18 digits of precision
    function getPrices(address[] calldata _tokens) public view returns (uint[] memory) {
        uint length = _tokens.length;
        uint[] memory response = new uint[](length);
        for (uint i = 0; i < length; i++) {  //xx LOW 95,108,174-179 use unchecked declaration to disable embedded safemath for i++
            response[i] = getPrice(_tokens[i]);
        }
        return response;
    }

    /// @notice Returns address balances for many tokens
    /// @param _address Wallet address
    /// @param _tokens Tokens addresses
    /// @return Balances
    function getBalances(address _address, address[] calldata _tokens) public view returns (uint[] memory) {
        uint length = _tokens.length;
        uint[] memory response = new uint[](length);
        for (uint i = 0; i < length; i++) {
            response[i] = IERC20(_tokens[i]).balanceOf(_address);
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
                : defaultCryptoCommission;
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
        return fiats;  //xx LOW 157-160,164-166 fiats are declared as a public variable with default getter function. This is duplication. Consider removal.
    }

    /// @notice Returns array of Coins addresses with different commissions
    /// @return Array of coins addresses
    function getCoins() public view returns (address[] memory) {
        return coins;
    }

    /// @notice Returns array of all known tokens to manage commissions
    /// @return Array of tokens addresses
    function getAllTokens() public view returns (address[] memory) {
        uint fiatsLength = fiats.length;
        uint coinsLength = coins.length;
        address[] memory responseTokens = new address[](fiatsLength + coinsLength);
        for (uint i = 0; i < fiatsLength; i++) {
            responseTokens[i] = fiats[i];
        }
        for (uint i = 0; i < coinsLength; i++) {
            responseTokens[fiatsLength + i] = coins[i];
        }
        return responseTokens;
    }

    /// @notice Returns all commissions and rewards data
    /// @return Default fiat commission
    /// @return Default coin commission
    /// @return Default referral reward percent
    /// @return Array of Token structs
    function getSettings() public view returns (  //xx LOW why do you need this function at all?
        int,
        int,
        uint,
        Token[] memory
        ) {
        address[] memory allTokens = getAllTokens();
        uint length = allTokens.length;
        Token[] memory responseTokens = new Token[](length);
        for (uint i; i < length; i++) {  //xx LOW prevent the warning from slither, use "uint i = 0;:
            responseTokens[i] = tokens[allTokens[i]];
        }

        return (
            defaultFiatCommission,
            defaultCryptoCommission,
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
        tokenData.price = !tokenData.isFiat && _skipCoinPrice  //xx WARNING why do you have it for "!tokenData.isFiat"?
            ? 0
            : getPrice(_address);
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
        for (uint i; i < _tokens.length; i++) {  //xx LOW prevent the warning from slither, use "uint i = 0;:
            response[i] = getTokenData(_tokens[i], _skipCoinPrice);
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
    /// @param _price Fiat price - unsigned number with 18 digits of precision  //xx MAJOR 91,248,263 why you say 18 decimals? USDT.decimals()==6, USDC.decimals()==6, for them the price will be PancakeLibrary.getAmountOut(10**IERC20(_token0).decimals(), reserve0, reserve1)==10**6
    /// @dev Only owner can manage prices
    function updatePrice(address _address, uint _price) public canUpdate {  //xx MAJOR centralization power risk. Hacker will get the full control over the oracle if he will be in control of one backend server with a private key. Consider the usage of "voting" by several oracle nodes. Committing prices with signatures.
        Token storage token = tokens[_address];
        if (token.price != _price) {
            token.price = _price;  //xx LOW emit event?
        }
        if (!token.isFiat) {
            token.isFiat = true;  //xx LOW instead, it's safer to require(token.isFiat);
            fiats.push(_address);
        }
    }

    /// @notice Update many fiats prices
    /// @param _fiats Array of tokens addresses
    /// @param _prices Fiats prices array - unsigned numbers with 18 digits of precision
    /// @dev Only owner can manage prices
    function updatePrices(address[] calldata _fiats, uint[] calldata _prices) public canUpdate {
        require (_fiats.length == _prices.length, "Data lengths do not match");
        for (uint i = 0; i < _fiats.length; i++) {
            updatePrice(_fiats[i], _prices[i]);
        }
    }

    /// @notice Remove the fiat mark from the token
    /// @param _address Token address
    /// @dev Only owner can use it
    /// @dev Necessary for rare cases, if for some reason the token got into the fiats list
    function removeTokenFromFiats(address _address) public onlyOwner {  //xx LOW use openzeppelin EnumerableSet
        Token storage token = tokens[_address];
        require (token.isFiat, "Token is not fiat");
        token.isFiat = false;
        for (uint i = 0; i < fiats.length; i++) {
            if (_address == fiats[i]) {
                delete fiats[i];  //xx MAJOR you have gaps in array, replace with the last one and use ".pop()"
                break;
            }
        }  //xx WARNING should it update the price?
    }

    /// @notice Remove the token from the coins list
    /// @param _address Token address
    /// @dev Only owner can use it
    function removeTokenFromCoins(address _address) public onlyOwner {
        for (uint i = 0; i < coins.length; i++) {
            if (_address == coins[i]) {
                delete coins[i];
                break;
            }
        }
    }

    /// @notice Set transfer fee percent for token
    /// @param _address Token address
    /// @param _fee Fee percent with 1000 decimals precision (20 = 2%)
    function setTokenTransferFee(address _address, uint _fee) public onlyOwner {
        Token storage token = tokens[_address];
        token.transferFee = _fee;
    }

    /// @notice Update default commissions and reward values
    /// @param _fiatCommission Default fiat commission
    /// @param _cryptoCommission Default coin commission
    /// @param _reward Default referral reward percent
    /// @dev Only owner can use it
    function updateDefaultSettings(  //xx LOW 313-399 it looks like it should not be part of the oracle
        int _fiatCommission,
        int _cryptoCommission,
        uint _reward
        ) public onlyOwner {  //xx LOW emit event
        defaultFiatCommission = _fiatCommission;
        defaultCryptoCommission = _cryptoCommission;
        defaultReward = _reward;
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
            require (tokensChanged.length == newValues.length, "Changed tokens length do not match values length");
            for (uint i = 0; i < tokensToCustom.length; i++) {
                Token storage token = tokens[tokensToCustom[i]];
                token.isCustomCommission = true;
                if (!token.isFiat) {
                    coins.push(tokensToCustom[i]);
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
                tokens[tokensToCustom[i]].commission = newValues[i];
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
    /// @param tokensChanged Array of tokens addresses that will receive changes
    /// @param newValues An array of percents corresponding to an array of tokens
    /// @dev Only owner can use it
    function updateReferralPercents(
        address[] calldata tokensToCustom,
        address[] calldata tokensToDefault,
        address[] calldata tokensChanged,
        uint[] calldata newValues
        ) public onlyOwner {
            require (tokensChanged.length == newValues.length, "Changed tokens length do not match values length");
            for (uint i = 0; i < tokensToCustom.length; i++) {
                tokens[tokensToCustom[i]].isCustomReward = true;
            }
            for (uint i = 0; i < tokensToDefault.length; i++) {
                tokens[tokensToCustom[i]].isCustomReward = false;
            }
            for (uint i = 0; i < tokensChanged.length; i++) {
                tokens[tokensToCustom[i]].reward = newValues[i];
            }
        }
}