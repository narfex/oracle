# Narfex Oracle

An oracle that looks to Pancakeswap contracts for token prices instead of external sources.

## Install Dependencies

`npm i`

## Compile

`npm run compile`

## Prepare account before deploy

Create a file names 'accounts.js' with the following contents
to the one level above the project directory

`
module.exports = {
	bsc: {
		address: 'your_wallet_address',
		privateKey: 'your_wallet_private_key'
	},
	bscscan: 'your_bscscan_api_key',
};
`

## Deploy to BSC

`npm run deployBSC`

## Verify

`npx hardhat verify --network bsc --constructor-args arguments.js "your_contract_address"`
