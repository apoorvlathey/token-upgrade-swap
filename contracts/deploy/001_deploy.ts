import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { utils } from "ethers";

const contractName = "TokenSwap";

const v1TokenAddress = "0x00";
const v2TokenAddress = "0x00";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  await deploy(contractName, {
    args: [v1TokenAddress, v2TokenAddress],
    from: deployer,
    log: true,
    gasPrice: utils.hexlify(utils.parseUnits("2", "gwei")),
  });
};
export default func;
func.tags = [contractName];
