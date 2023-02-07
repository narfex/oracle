const { ethers } = require("hardhat");

const main = async () => {
  const OracleContract = await ethers.getContractFactory("NarfexOracle");
  const oracle = await OracleContract.deploy(
      "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", // USDC
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