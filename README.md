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

