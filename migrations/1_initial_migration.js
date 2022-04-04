const Migrations = artifacts.require("Migrations");
const SignatureVerifier = artifacts.require("SignatureVerifier");
const Particlon = artifacts.require("Particlon");
const PUT = artifacts.require("ParticlonUtilityToken");

const ChargedParticlesMock = artifacts.require("ChargedParticlesMock");
const ChargedStateMock = artifacts.require("ChargedStateMock");

module.exports = function (deployer, network, accounts) {
  deployer.then(async () => {
    await deployer.deploy(Migrations);
    await deployer.deploy(SignatureVerifier);
    // await deployer.deploy(Particlon, SignatureVerifier.address);
    await deployer.deploy(Particlon);
    await deployer.deploy(PUT);

    if (network === 'test') {
      await deployer.deploy(ChargedParticlesMock);
      await deployer.deploy(ChargedStateMock);
    }
  });
};
