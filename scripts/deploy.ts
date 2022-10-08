import hre from "hardhat";
import { ethers } from "hardhat";

import { Contract } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { deployContractWithoutArgs, getChainId, storeAddresses } from "./utils";

import { deployAccumulator, deployCounter, deployNotary, deploySocket, deployVault, deployVerifier } from "../scripts/contracts";
import { executorAddress, totalDestinations } from "./config";

export const main = async () => {
  try {
    // assign deployers
    const { getNamedAccounts } = hre;
    const { socketOwner, counterOwner } = await getNamedAccounts();

    const socketSigner: SignerWithAddress = await ethers.getSigner(socketOwner);
    const counterSigner: SignerWithAddress = await ethers.getSigner(counterOwner);

    // notary
    const signatureVerifier: Contract = await deployContractWithoutArgs("SignatureVerifier", socketSigner);
    const notary: Contract = await deployNotary(signatureVerifier, socketSigner);

    // socket
    const hasher: Contract = await deployContractWithoutArgs("Hasher", socketSigner);
    const vault: Contract = await deployVault(socketSigner);
    const socket: Contract = await deploySocket(hasher, vault, socketSigner);

    // plug deployments
    const verifier: Contract = await deployVerifier(notary, socket, counterSigner)
    const counter: Contract = await deployCounter(socket, counterSigner);
    console.log("Contracts deployed!");

    // configure
    const chainId = await getChainId();

    await socket.connect(socketSigner).grantExecutorRole(executorAddress[chainId]);
    console.log(`Assigned executor role to ${executorAddress[chainId]}!`)

    const addresses = {
      counter: counter.address,
      hasher: hasher.address,
      notary: notary.address,
      signatureVerifier: signatureVerifier.address,
      socket: socket.address,
      vault: vault.address,
      verifier: verifier.address
    }

    // accum & deaccum deployments
    for (let index = 0; index < totalDestinations.length; index++) {
      const fastAccum: Contract = await deployAccumulator(socket.address, notary.address, totalDestinations[index], socketSigner);
      const slowAccum: Contract = await deployAccumulator(socket.address, notary.address, totalDestinations[index], socketSigner);
      const deaccum: Contract = await deployContractWithoutArgs("SingleDeaccum", socketSigner);
      console.log(`Deployed accum and deaccum for ${totalDestinations[index]} chain id`);

      addresses[`fastAccum-${totalDestinations[index]}`] = fastAccum.address;
      addresses[`slowAccum-${totalDestinations[index]}`] = slowAccum.address;
      addresses[`deaccum-${totalDestinations[index]}`] = deaccum.address;
    }

    await storeAddresses(addresses, chainId);
  } catch (error) {
    console.log("Error in deploying setup contracts", error);
    throw error;
  }
};

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
