import { ethers, network, waffle } from "hardhat";
import { parseEther } from "@ethersproject/units";
import { AddressZero, MaxUint256, HashZero } from "@ethersproject/constants";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Signer } from "ethers";
import { solidity } from "ethereum-waffle";
import chai from "chai";

chai.use(solidity);
const { expect } = chai;
const { deployContract } = waffle;

// artifacts
import TokenSwapArtifact from "../artifacts/contracts/TokenSwap.sol/TokenSwap.json";
import V1TokenArtifact from "../artifacts/contracts/mocks/V1Token.sol/V1Token.json";
import V2TokenArtifact from "../artifacts/contracts/mocks/DGVCImplementation.sol/DGVCImplementation.json";

// types
import { TokenSwap, DGVCImplementation, V1Token } from "../typechain";

describe("TokenSwap", () => {
  let tokenSwap: TokenSwap;
  let v1Token: V1Token;
  let v2Token: DGVCImplementation;

  let deployer: SignerWithAddress;
  let user: SignerWithAddress;

  before(async () => {
    [deployer, user] = await ethers.getSigners();

    // deploy contracts
    v1Token = (await deployContract(deployer, V1TokenArtifact, [
      user.address,
    ])) as V1Token;
    v2Token = (await deployContract(
      deployer,
      V2TokenArtifact
    )) as DGVCImplementation;
    await v2Token.connect(deployer).init(AddressZero);

    tokenSwap = (await deployContract(deployer, TokenSwapArtifact, [
      v1Token.address,
      v2Token.address,
    ])) as TokenSwap;

    // fund tokenSwap with v2 tokens
    await v2Token
      .connect(deployer)
      .transfer(tokenSwap.address, parseEther("12000000"));

    // user should approve tokenSwap to spend v1 tokens
    await v1Token.connect(user).approve(tokenSwap.address, MaxUint256);
  });

  it("should bridge specific amount of V1 tokens to V2", async () => {
    const toBridgeAmount = parseEther("100");

    const initialV1Balance = await v1Token.balanceOf(user.address);
    const initialV2Balance = await v2Token.balanceOf(user.address);
    // bridge
    await tokenSwap.connect(user).bridge(toBridgeAmount);

    const finalV1Balance = await v1Token.balanceOf(user.address);
    const finalV2Balance = await v2Token.balanceOf(user.address);

    expect(initialV1Balance.sub(finalV1Balance)).to.eq(toBridgeAmount);
    expect(finalV2Balance.sub(initialV2Balance)).to.eq(toBridgeAmount);
  });

  it(`should bridge ALL of user's V1 tokens to V2`, async () => {
    const initialV1Balance = await v1Token.balanceOf(user.address);
    const initialV2Balance = await v2Token.balanceOf(user.address);
    // bridge
    await tokenSwap.connect(user).bridgeAll();

    const finalV1Balance = await v1Token.balanceOf(user.address);
    const finalV2Balance = await v2Token.balanceOf(user.address);

    expect(finalV1Balance).to.eq(0);
    expect(finalV2Balance.sub(initialV2Balance)).to.eq(initialV1Balance);
  });
});
