const { ethers } = require("hardhat");

const main = async () => {
  const OracleContract = await ethers.getContractFactory("NarfexOracle");
  const oracle = await OracleContract.deploy(
      "0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73", // PancakeFactory official contract on BSC
      "0x55d398326f99059fF775485246999027B3197955", // Tether official contract in BSC
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