// SPDX-License-Identifier: MIT

// IChargedSettings.sol -- Part of the Charged Particles Protocol
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

/**
 * @notice Interface for Charged Settings
 */
interface IChargedSettings {
    /***********************************|
    |         Only NFT Creator          |
    |__________________________________*/

    function setCreatorAnnuities(
        address contractAddress,
        uint256 tokenId,
        address creator,
        uint256 annuityPercent
    ) external;

    function setCreatorAnnuitiesRedirect(
        address contractAddress,
        uint256 tokenId,
        address receiver
    ) external;

    /***********************************|
    |      Only NFT Contract Owner      |
    |__________________________________*/

    function setRequiredWalletManager(
        address contractAddress,
        string calldata walletManager
    ) external;

    function setRequiredBasketManager(
        address contractAddress,
        string calldata basketManager
    ) external;

    function setAssetTokenRestrictions(
        address contractAddress,
        bool restrictionsEnabled
    ) external;

    function setAllowedAssetToken(
        address contractAddress,
        address assetToken,
        bool isAllowed
    ) external;

    function setAssetTokenLimits(
        address contractAddress,
        address assetToken,
        uint256 depositMin,
        uint256 depositMax
    ) external;

    function setMaxNfts(
        address contractAddress,
        address nftTokenAddress,
        uint256 maxNfts
    ) external;
}
