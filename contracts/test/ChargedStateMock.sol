// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract ChargedStateMock {
  function setTemporaryLock(
    address contractAddress,
    uint256 tokenId,
    bool isLocked
  )
    external
  {
    // no-op
  }
}
