// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISignatureVerifier {
    function verify(
        address _signer,
        address _to,
        uint256 _amount,
        bytes memory signature
    ) external pure returns (bool);
}
