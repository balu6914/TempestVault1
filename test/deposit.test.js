const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("TempestProVault Deposit", function () {
  let TempestProVault;
  let tempestProVault;
  let owner;
  let addr1;

  beforeEach(async function () {
    [owner, addr1] = await ethers.getSigners();

    // Deploy the TempestProVault contract
    TempestProVault = await ethers.getContractFactory("TempestProVault");
    tempestProVault = await TempestProVault.deploy(
      // Pass constructor arguments here
    );
    await tempestProVault.deployed();
  });

  it("Should allow depositing liquidity into the vault", async function () {
    // Get the initial balances of token0 and token1 for the vault and the depositor
    const initialBalanceVaultToken0 = await tempestProVault.token0.balanceOf(tempestProVault.address);
    const initialBalanceVaultToken1 = await tempestProVault.token1.balanceOf(tempestProVault.address);
    const initialBalanceAddr1Token0 = await tempestProVault.token0.balanceOf(addr1.address);
    const initialBalanceAddr1Token1 = await tempestProVault.token1.balanceOf(addr1.address);

    // Approve token transfers
    await tempestProVault.token0.connect(addr1).approve(tempestProVault.address, amount0Desired);
    await tempestProVault.token1.connect(addr1).approve(tempestProVault.address, amount1Desired);
   
    // Deposit liquidity into the vault
    await tempestProVault.connect(addr1).deposit(amount0Desired, amount1Desired, amount0Min, amount1Min, owner.address);

    // Get the final balances of token0 and token1 for the vault and the depositor
    const finalBalanceVaultToken0 = await tempestProVault.token0.balanceOf(tempestProVault.address);
    const finalBalanceVaultToken1 = await tempestProVault.token1.balanceOf(tempestProVault.address);
    const finalBalanceAddr1Token0 = await tempestProVault.token0.balanceOf(addr1.address);
    const finalBalanceAddr1Token1 = await tempestProVault.token1.balanceOf(addr1.address);

    // Assert that the liquidity has been deposited successfully
    expect(finalBalanceVaultToken0).to.equal(initialBalanceVaultToken0.add(amount0Desired));
    expect(finalBalanceVaultToken1).to.equal(initialBalanceVaultToken1.add(amount1Desired));
    expect(finalBalanceAddr1Token0).to.equal(initialBalanceAddr1Token0.sub(amount0Desired));
    expect(finalBalanceAddr1Token1).to.equal(initialBalanceAddr1Token1.sub(amount1Desired));
  });
});
