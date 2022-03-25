// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// import "@opengsn/gsn/contracts/BaseRelayRecipient.sol";
import "@opengsn/contracts/src/BaseRelayRecipient.sol";

contract RelayRecipient is BaseRelayRecipient {
    function versionRecipient() external pure override returns (string memory) {
        return "1.0.0-beta.1/charged-particles.relay.recipient";
    }
}
