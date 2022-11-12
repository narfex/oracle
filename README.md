## Narfex Oracle

An oracle that looks to Pancakeswap contracts for token prices instead of external sources. Using PancakeFactory contract
```solidity
    contract PancakeFactory {
    	function getPair(address _token0, address _token1) external view virtual returns (address pairAddress);
}
```

and using PancakePair contract
 ```solidity
    contract PancakePair {
    	address public token0;
    	address public token1;
    	function getReserves() public view virtual returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);
}
}
```

## ***How we can get prices of tokens from pancakeswap***
1. In this function we can get address of pair in PancakeFactory
```solidity
    function getPair(address _token0, address _token1) public view returns (address pairAddress)
```
    `returns` address of pair in pancakeswap


2. Searching for price of _token0 in pair
```solidity
   function getRatio(address _token0, address _token1) public view returns (uint)
```
    `returns` price of `_token0` in wei

3. Getting price of second token in pair (in this case USDT)
```solidity
   function getPrice(address _token) public view returns (uint)
```
    `returns` price of `USDT`

4. Getting price of native token (BNB or WBNB in USDT).   
```solidity
   function getUSDPrice(address _token) public view returns (uint)
```
    `returns` price of `BNB` in USDT
