const { ethers } = require("hardhat");

const main = async () => {
  const OracleContract = await ethers.getContractFactory("NarfexOracle");
  const oracle = await OracleContract.deploy(
      "0x7ef95a0FEE0Dd31b22626fA2e10Ee6A223F8a684", // Tether official contract in BSC
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