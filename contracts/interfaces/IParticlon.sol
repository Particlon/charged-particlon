// SPDX-License-Identifier: MIT

// Particlon.sol -- Part of the Charged Particles Protocol
// Copyright (c) 2021 Firma Lux, Inc. <https://charged.fi>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

pragma solidity ^0.8.0;

// pragma experimental ABIEncoderV2;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/utils/math/SafeMath.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/utils/Counters.sol";
// import "@openzeppelin/contracts/utils/Address.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// import "./BlackholePrevention.sol";
// import "./RelayRecipient.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IParticlon is IERC721 {
    enum EMintPhase {
        CLOSED,
        CLAIM,
        WHITELIST,
        PUBLIC
    }
    /// @notice Andy was here
    event NewBaseURI(string indexed _uri);
    event NewSignerAddress(address indexed signer);
    event NewMintPhase(EMintPhase indexed mintPhase);
    event NewMintPrice(uint256 price);

    event AssetTokenSet(address indexed assetToken);
    event ChargedStateSet(address indexed chargedState);
    event ChargedSettingsSet(address indexed chargedSettings);
    event ChargedParticlesSet(address indexed chargedParticles);

    event SalePriceSet(uint256 indexed tokenId, uint256 salePrice);
    event CreatorRoyaltiesSet(uint256 indexed tokenId, uint256 royaltiesPct);
    event ParticlonSold(
        uint256 indexed tokenId,
        address indexed oldOwner,
        address indexed newOwner,
        uint256 salePrice,
        address creator,
        uint256 creatorRoyalties
    );
    event RoyaltiesClaimed(address indexed receiver, uint256 amountClaimed);

    /***********************************|
    |              Public               |
    |__________________________________*/

    function creatorOf(uint256 tokenId) external view returns (address);

    function getSalePrice(uint256 tokenId) external view returns (uint256);

    function getLastSellPrice(uint256 tokenId) external view returns (uint256);

    function getCreatorRoyalties(address account)
        external
        view
        returns (uint256);

    function getCreatorRoyaltiesPct(uint256 tokenId)
        external
        view
        returns (uint256);

    function getCreatorRoyaltiesReceiver(uint256 tokenId)
        external
        view
        returns (address);

    function buyParticlon(uint256 tokenId, uint256 gasLimit)
        external
        payable
        returns (bool);

    function claimCreatorRoyalties() external returns (uint256);

    // function createParticlonForSale(
    //     address creator,
    //     address receiver,
    //     // string memory tokenMetaUri,
    //     uint256 royaltiesPercent,
    //     uint256 salePrice
    // ) external returns (uint256 newTokenId);

    function mint(uint256 amount) external payable returns (bool);

    function mintWhitelist(uint256 amount, bytes calldata signature)
        external
        payable
        returns (bool);

    function mintFree(uint256 amount, bytes calldata signature)
        external
        returns (bool);

    // function batchParticlonsForSale(
    //     address creator,
    //     uint256 annuityPercent,
    //     uint256 royaltiesPercent,
    //     uint256[] calldata salePrices
    // ) external;

    // function createParticlonsForSale(
    //     address creator,
    //     address receiver,
    //     uint256 royaltiesPercent,
    //     // string[] calldata tokenMetaUris,
    //     uint256[] calldata salePrices
    // ) external returns (bool);

    // Andy was here
    /// @dev Using a baseURI removes the need to set each tokenURI
    function baseURI() external view returns (string memory);

    /***********************************|
    |     Only Token Creator/Owner      |
    |__________________________________*/

    function setSalePrice(uint256 tokenId, uint256 salePrice) external;

    function setRoyaltiesPct(uint256 tokenId, uint256 royaltiesPct) external;

    function setCreatorRoyaltiesReceiver(uint256 tokenId, address receiver)
        external;
}
