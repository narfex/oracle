const { ethers } = require("hardhat");

const main = async () => {
  const OracleContract = await ethers.getContractFactory("NarfexOracle");
  const oracle = await OracleContract.deploy(
      "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // USDC
  );

  await oracle.deployed();

  console.log("Oracle deployed:", oracle.address);
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });