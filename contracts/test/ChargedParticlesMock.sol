// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract ChargedParticlesMock {
  function energizeParticle(
    address /* contractAddress */,
    uint256 /* tokenId */,
    string calldata /* walletManagerId */,
    address /* assetToken */,
    uint256 assetAmount,
    address /* referrer */
  )
    external pure returns (uint256 yieldTokensAmount)
  {
    yieldTokensAmount = assetAmount;
  }
}
