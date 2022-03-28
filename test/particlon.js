const SignatureVerifier = artifacts.require("SignatureVerifier");
const Particlon = artifacts.require("Particlon");
const PUT = artifacts.require("ParticlonUtilityToken");

/*
 * uncomment accounts to access the test accounts made available by the
 * Ethereum client
 * See docs: https://www.trufflesuite.com/docs/truffle/testing/writing-tests-in-javascript
 */
contract("Particlon & PUT", async accounts => {
  it("should assert true", async function () {
    const signatureVerifier = await SignatureVerifier.deployed();
    const particlon = await Particlon.deployed(signatureVerifier.address);
    const put = await PUT.deployed();

    await put.mint(particlon.address, web3.utils.toBN("1000000000000000000000"));

    await particlon.setMintPhase(3); // 3 == PUBLIC MINT

    // await particlon.mintParticlonsPublic(10)
    return assert.isTrue(true);
  });
});
