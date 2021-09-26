import { Dispatch, SetStateAction } from "react";
import { ethers, Signer as SignerAlias } from "ethers";

export type Web3Provider = ethers.providers.Web3Provider | undefined;

export type setProvider = Dispatch<SetStateAction<Web3Provider>>;

export type Signer = SignerAlias;
