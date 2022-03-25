const Migrations = artifacts.require("Migrations");
const SignatureVerifier = artifacts.require("SignatureVerifier");
const Particlon = artifacts.require("Particlon");
const PUT = artifacts.require("ParticlonUtilityToken");

module.exports = function (deployer, network, accounts) {
  deployer.then(async () => {
    await deployer.deploy(Migrations);
    await deployer.deploy(SignatureVerifier);
    await deployer.deploy(Particlon, SignatureVerifier.address);
    await deployer.deploy(PUT);
  });
};
