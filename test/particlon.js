
const SignatureVerifier = artifacts.require("SignatureVerifier");
const Particlon = artifacts.require("Particlon");
const PUT = artifacts.require("ParticlonUtilityToken");

const ChargedParticlesMock = artifacts.require("ChargedParticlesMock");
const ChargedStateMock = artifacts.require("ChargedStateMock");

/*
 * uncomment accounts to access the test accounts made available by the
 * Ethereum client
 * See docs: https://www.trufflesuite.com/docs/truffle/testing/writing-tests-in-javascript
 */
contract("Particlon & PUT", async accounts => {
  it("should assert true", async function () {
    // const signatureVerifier = await SignatureVerifier.deployed();
    // const particlon = await Particlon.deployed(signatureVerifier.address);
    const particlon = await Particlon.deployed();
    const put = await PUT.deployed();

    const chargedParticlesMock = await ChargedParticlesMock.deployed();
    const chargedStateMock = await ChargedStateMock.deployed();

    await put.mint(particlon.address, web3.utils.toWei("15000000", "ether"));

    // // DO These First!

    // Set Charged Particles
    await particlon.setChargedParticles(chargedParticlesMock.address);

    // Set Charged State
    await particlon.setChargedState(chargedStateMock.address);


    // // Then Initializee Particlon

    // // Set Base URI
    const baseURI = "my base uri here";
    await particlon.setURI(baseURI);

    // // Set Mint Phase
    const mintPhase = 3; // 3 == PUBLIC MINT
    await particlon.setMintPhase(mintPhase);

    // Set Asset Token
    await particlon.setAssetToken(put.address);


    // Then Mint!!

    const price = 0.15;
    const amountToMint = 10;
    const payment = web3.utils.toWei('' + (amountToMint * price), 'ether');

    await particlon.mint.call(amountToMint, { value: payment });
    await particlon.withdrawEther(accounts[1], payment);

    return assert.isTrue(true);
  });
});
