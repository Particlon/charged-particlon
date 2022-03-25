# charged-particlon
Particlon is the first generative NFT drop from Charged Particles, powered by VASI (Virtual Art Systems &amp; Integration).

# Setup
Run:
1) `npm install`

2) `npm run compile`

3) `npm run test`

If there are no errors, you can now deploy the contracts.

In the `config`, set your `infura` key and `networkId`.

This assumes the `SignatureVerifier` is already deployed. (TODO)

First, the $PUT token needs to be deployed. Run
- `npm run deployPut` (TODO)

Then run
- `npm run deployParticlon` (TODO)

After that, you need to fill the `Particlon` contract with some $PUT tokens.
That way, when people mint, they will be able to recieve the tokens nested inside the NFT itself.
How? Powered by black magic invented by [Charged Particles](https://charged.fi])!
