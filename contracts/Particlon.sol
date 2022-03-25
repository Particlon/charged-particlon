// SPDX-License-Identifier: MIT

// ParticlonB.sol -- Part of the Charged Particles Protocol
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
//pragma experimental ABIEncoderV2; // default since 0.8

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IParticlon.sol";
import "./interfaces/IUniverse.sol";
import "./interfaces/IChargedState.sol";
import "./interfaces/IChargedSettings.sol";
import "./interfaces/IChargedParticles.sol";

import "./interfaces/IERC721Consumable.sol";

// import "./lib/SignatureVerifier.sol";
import "./interfaces/ISignatureVerifier.sol";

import "./lib/TokenInfo.sol";
import "./lib/BlackholePrevention.sol";
import "./lib/RelayRecipient.sol";

contract Particlon is
    IParticlon,
    ERC721,
    IERC721Consumable,
    Ownable,
    RelayRecipient,
    ReentrancyGuard,
    BlackholePrevention
{
    // using SafeMath for uint256; // not needed since solidity 0.8
    using TokenInfo for address payable;
    // using Counters for Counters.Counter;

    address internal _signer;

    /// @notice Using the same naming convention to denote current supply as ERC721Enumerable
    uint256 public totalSupply;
    uint256 public constant MAX_SUPPLY = 10069;
    uint256 public constant PRICE = 0.15 ether;

    uint256 internal constant PERCENTAGE_SCALE = 1e4; // 10000  (100%)
    uint256 internal constant MAX_ROYALTIES = 8e3; // 8000   (80%)

    IUniverse internal _universe;
    IChargedState internal _chargedState;
    IChargedSettings internal _chargedSettings;
    IChargedParticles internal _chargedParticles;

    IERC20 internal _assetToken;
    ISignatureVerifier internal immutable _signatureVerifier; // This right here drops the size from 29kb to 15kb

    // Counters.Counter internal _tokenIds;

    /// @notice The baseURI may change from an API-based to an ipfs-based
    string internal _uri;
    bool internal _paused;
    // Mapping from token ID to consumer address
    mapping(uint256 => address) _tokenConsumers;

    mapping(uint256 => address) internal _tokenCreator;
    mapping(uint256 => uint256) internal _tokenCreatorRoyaltiesPct;
    mapping(uint256 => address) internal _tokenCreatorRoyaltiesRedirect;
    mapping(address => uint256) internal _tokenCreatorClaimableRoyalties;

    mapping(uint256 => uint256) internal _tokenSalePrice;
    mapping(uint256 => uint256) internal _tokenLastSellPrice;

    /// @notice Adhere to limits per whitelisted wallet for whitelist mint phase
    mapping(address => bool) internal _whitelistedAddressMinted;

    /// @notice Address used to generate cryptographic signatures for whitelisted addresses

    /// @notice set to CLOSED by default
    EMintPhase public mintPhase;

    /***********************************|
    |          Initialization           |
    |__________________________________*/

    constructor(address signatureVerifier) ERC721("Particlon", "PART") {
        _signatureVerifier = ISignatureVerifier(signatureVerifier);
    }

    /***********************************|
    |              Public               |
    |__________________________________*/

    function baseURI() external view override returns (string memory) {
        return _uri;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, ERC721)
        returns (bool)
    {
        return
            interfaceId == type(IERC721Consumable).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @notice Andy was here
    function setURI(string memory uri) external onlyOwner {
        _uri = uri;
        emit NewBaseURI(uri);
    }

    /**
     * @dev See {IERC721Consumable-consumerOf}
     */
    function consumerOf(uint256 _tokenId) external view returns (address) {
        require(
            _exists(_tokenId),
            "ERC721Consumable: consumer query for nonexistent token"
        );
        return _tokenConsumers[_tokenId];
    }

    function creatorOf(uint256 tokenId)
        external
        view
        virtual
        override
        returns (address)
    {
        return _tokenCreator[tokenId];
    }

    function getSalePrice(uint256 tokenId)
        external
        view
        virtual
        override
        returns (uint256)
    {
        return _tokenSalePrice[tokenId];
    }

    function getLastSellPrice(uint256 tokenId)
        external
        view
        virtual
        override
        returns (uint256)
    {
        return _tokenLastSellPrice[tokenId];
    }

    function getCreatorRoyalties(address account)
        external
        view
        virtual
        override
        returns (uint256)
    {
        return _tokenCreatorClaimableRoyalties[account];
    }

    function getCreatorRoyaltiesPct(uint256 tokenId)
        external
        view
        virtual
        override
        returns (uint256)
    {
        return _tokenCreatorRoyaltiesPct[tokenId];
    }

    function getCreatorRoyaltiesReceiver(uint256 tokenId)
        external
        view
        virtual
        override
        returns (address)
    {
        return _creatorRoyaltiesReceiver(tokenId);
    }

    function claimCreatorRoyalties()
        external
        virtual
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        return _claimCreatorRoyalties(_msgSender());
    }

    /***********************************|
    |      Create Multiple Particlons   |
    |__________________________________*/

    /// @notice Andy was here
    function mintParticlonsPublic(uint256 amount)
        external
        payable
        virtual
        override
        /// string[] calldata tokenMetaUris
        whenNotPaused
        whenMintPhase(EMintPhase.WHITELIST)
        whenRemainingSupply
        handlePayment(amount)
        returns (bool)
    {
        uint256 newTokenId = totalSupply + 1;
        totalSupply += amount;
        // TODO add max supply
        for (uint256 i; i < amount; i++) {
            _createChargedParticlon(
                ++newTokenId, // increment, then return value
                msg.sender // creator
                // 0, // annuityPercent
                // 0, // royaltiesPercent
                // 0 // salePrice
            );
        }

        return true;
    }

    /// @notice Andy was here
    function mintParticlonsWhitelist(uint256 amount, bytes calldata signature)
        external
        payable
        virtual
        override
        /// string[] calldata tokenMetaUris
        whenNotPaused
        whenMintPhase(EMintPhase.PUBLIC)
        whenRemainingSupply
        returns (bool)
    {
        uint256 newTokenId = totalSupply;
        totalSupply += amount;
        require(
            _signatureVerifier.verify(_signer, msg.sender, amount, signature),
            "INVALID SIGNATURE"
        );
        require(
            !_whitelistedAddressMinted[msg.sender],
            "ALREADY CLAIMED WHITELIST"
        );
        _whitelistedAddressMinted[msg.sender] = true;
        for (uint256 i; i < amount; i++) {
            _createChargedParticlon(
                ++newTokenId, // increment, then return value
                msg.sender // creator
                // 0, // annuityPercent
                // 0, // royaltiesPercent
                // 0 // salePrice
            );
        }

        return true;
    }

    /***********************************|
    |           Buy Particlons          |
    |__________________________________*/

    function buyParticlon(uint256 tokenId, uint256 gasLimit)
        external
        payable
        virtual
        override
        nonReentrant
        whenNotPaused
        returns (bool)
    {
        _buyParticlon(tokenId, gasLimit);
        return true;
    }

    /***********************************|
    |     Only Token Creator/Owner      |
    |__________________________________*/

    function setSalePrice(uint256 tokenId, uint256 salePrice)
        external
        virtual
        override
        whenNotPaused
        onlyTokenOwnerOrApproved(tokenId)
    {
        _setSalePrice(tokenId, salePrice);
    }

    function setRoyaltiesPct(uint256 tokenId, uint256 royaltiesPct)
        external
        virtual
        override
        whenNotPaused
        onlyTokenCreator(tokenId)
        onlyTokenOwnerOrApproved(tokenId)
    {
        _setRoyaltiesPct(tokenId, royaltiesPct);
    }

    function setCreatorRoyaltiesReceiver(uint256 tokenId, address receiver)
        external
        virtual
        override
        whenNotPaused
        onlyTokenCreator(tokenId)
    {
        _tokenCreatorRoyaltiesRedirect[tokenId] = receiver;
    }

    /**
     * @dev See {IERC721Consumable-changeConsumer}
     */
    function changeConsumer(address _consumer, uint256 _tokenId) external {
        address owner = this.ownerOf(_tokenId);
        require(
            msg.sender == owner ||
                msg.sender == getApproved(_tokenId) ||
                isApprovedForAll(owner, msg.sender),
            "ERC721Consumable: changeConsumer caller is not owner nor approved"
        );
        _changeConsumer(owner, _consumer, _tokenId);
    }

    /***********************************|
    |          Only Admin/DAO           |
    |__________________________________*/

    // Andy was here

    function setSignerAddress(address signer) external onlyOwner {
        _signer = signer;
        emit NewSignerAddress(signer);
    }

    function setAssetToken(address assetToken) external onlyOwner {
        _assetToken = IERC20(assetToken);
        emit AssetTokenSet(assetToken);
    }

    function setMintPhase(EMintPhase _mintPhase) external onlyOwner {
        mintPhase = _mintPhase;
        emit NewMintPhase(_mintPhase);
    }

    function setPausedState(bool state) external virtual onlyOwner {
        _paused = state;
        emit PausedStateSet(state);
    }

    /**
     * @dev Setup the ChargedParticles Interface
     */
    function setUniverse(address universe) external virtual onlyOwner {
        _universe = IUniverse(universe);
        emit UniverseSet(universe);
    }

    /**
     * @dev Setup the ChargedParticles Interface
     */
    function setChargedParticles(address chargedParticles)
        external
        virtual
        onlyOwner
    {
        _chargedParticles = IChargedParticles(chargedParticles);
        emit ChargedParticlesSet(chargedParticles);
    }

    /// @dev Setup the Charged-State Controller
    function setChargedState(address stateController)
        external
        virtual
        onlyOwner
    {
        _chargedState = IChargedState(stateController);
        emit ChargedStateSet(stateController);
    }

    /// @dev Setup the Charged-Settings Controller
    function setChargedSettings(address settings) external virtual onlyOwner {
        _chargedSettings = IChargedSettings(settings);
        emit ChargedSettingsSet(settings);
    }

    function setTrustedForwarder(address _trustedForwarder)
        external
        virtual
        onlyOwner
    {
        _setTrustedForwarder(_trustedForwarder); // Andy was here, trustedForwarder is already defined in opengsn/contracts/src/BaseRelayRecipient.sol
    }

    /***********************************|
    |          Only Admin/DAO           |
    |      (blackhole prevention)       |
    |__________________________________*/

    function withdrawEther(address payable receiver, uint256 amount)
        external
        onlyOwner
    {
        _withdrawEther(receiver, amount);
    }

    function withdrawErc20(
        address payable receiver,
        address tokenAddress,
        uint256 amount
    ) external onlyOwner {
        _withdrawERC20(receiver, tokenAddress, amount);
    }

    function withdrawERC721(
        address payable receiver,
        address tokenAddress,
        uint256 tokenId
    ) external onlyOwner {
        _withdrawERC721(receiver, tokenAddress, tokenId);
    }

    /***********************************|
    |         Private Functions         |
    |__________________________________*/

    /**
     * @dev Changes the consumer
     * Requirement: `tokenId` must exist
     */
    function _changeConsumer(
        address _owner,
        address _consumer,
        uint256 _tokenId
    ) internal {
        _tokenConsumers[_tokenId] = _consumer;
        emit ConsumerChanged(_owner, _consumer, _tokenId);
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _tokenId
    ) internal virtual override(ERC721) {
        super._beforeTokenTransfer(_from, _to, _tokenId);

        _changeConsumer(_from, address(0), _tokenId);
    }

    function _setSalePrice(uint256 tokenId, uint256 salePrice)
        internal
        virtual
    {
        _tokenSalePrice[tokenId] = salePrice;
        emit SalePriceSet(tokenId, salePrice);
    }

    function _setRoyaltiesPct(uint256 tokenId, uint256 royaltiesPct)
        internal
        virtual
    {
        require(royaltiesPct <= MAX_ROYALTIES, "PRT:E-421"); // Andy was here
        _tokenCreatorRoyaltiesPct[tokenId] = royaltiesPct;
        emit CreatorRoyaltiesSet(tokenId, royaltiesPct);
    }

    function _creatorRoyaltiesReceiver(uint256 tokenId)
        internal
        view
        virtual
        returns (address)
    {
        address receiver = _tokenCreatorRoyaltiesRedirect[tokenId];
        if (receiver == address(0x0)) {
            receiver = _tokenCreator[tokenId];
        }
        return receiver;
    }

    // Andy was here
    function _createChargedParticlon(uint256 newTokenId, address creator)
        internal
        virtual
    // uint256 annuityPercent,
    // uint256 royaltiesPercent,
    // uint256 salePrice
    {
        // _tokenIds.increment();

        _safeMint(creator, newTokenId, "");
        _tokenCreator[newTokenId] = creator;

        // _setTokenURI(newTokenId, tokenMetaUri);

        // if (royaltiesPercent > 0) {
        //     _setRoyaltiesPct(newTokenId, royaltiesPercent);
        // }

        // if (salePrice > 0) {
        //     _setSalePrice(newTokenId, salePrice);
        // }

        // if (annuityPercent > 0) {
        //     _chargedSettings.setCreatorAnnuities(
        //         address(this),
        //         newTokenId,
        //         creator,
        //         annuityPercent
        //     );
        // }

        uint256 assetAmount = _getAssetAmount(newTokenId);
        _chargeParticlon(
            newTokenId,
            "generic",
            address(_assetToken),
            assetAmount,
            owner()
        );
    }

    /// @notice Tokenomics
    function _getAssetAmount(uint256 tokenId) internal pure returns (uint256) {
        // TODO actually implement the tokenomics
        if (tokenId > 9000) {
            return 468 * 10**18;
        } else if (tokenId > 6000) {
            return 500 * 10**18;
        } else if (tokenId > 3000) {
            return 1000 * 10**18;
        } else if (tokenId > 1000) {
            return 1500 * 10**18;
        }
        return 2500 * 10**18;
    }

    function _chargeParticlon(
        uint256 tokenId,
        string memory walletManagerId,
        address assetToken,
        uint256 assetAmount,
        address referrer
    ) internal virtual {
        /// Not needed since the assetTokens will reside in this contracts in the first place
        // _collectAssetToken(_msgSender(), assetToken, assetAmount);

        // IERC20(assetToken).approve(address(_chargedParticles), assetAmount);

        _chargedParticles.energizeParticle(
            address(this),
            tokenId,
            walletManagerId,
            assetToken,
            assetAmount,
            referrer
        );
    }

    function _buyParticlon(uint256 _tokenId, uint256 _gasLimit)
        internal
        virtual
        returns (
            address contractAddress,
            uint256 tokenId,
            address oldOwner,
            address newOwner,
            uint256 salePrice,
            address royaltiesReceiver,
            uint256 creatorAmount
        )
    {
        contractAddress = address(this);
        tokenId = _tokenId;
        salePrice = _tokenSalePrice[_tokenId];
        require(salePrice > 0, "PRT:E-416");
        require(msg.value >= salePrice, "PRT:E-414");

        uint256 ownerAmount = salePrice;
        creatorAmount;
        oldOwner = ownerOf(_tokenId);
        newOwner = _msgSender();

        // Creator Royalties
        royaltiesReceiver = _creatorRoyaltiesReceiver(_tokenId);
        uint256 royaltiesPct = _tokenCreatorRoyaltiesPct[_tokenId];
        uint256 lastSellPrice = _tokenLastSellPrice[_tokenId];
        if (
            royaltiesPct > 0 && lastSellPrice > 0 && salePrice > lastSellPrice
        ) {
            creatorAmount =
                ((salePrice - lastSellPrice) * royaltiesPct) /
                PERCENTAGE_SCALE;
            ownerAmount -= creatorAmount;
        }
        _tokenLastSellPrice[_tokenId] = salePrice;

        // Reserve Royalties for Creator
        // Andy was here - removed SafeMath
        if (creatorAmount > 0) {
            _tokenCreatorClaimableRoyalties[royaltiesReceiver] =
                _tokenCreatorClaimableRoyalties[royaltiesReceiver] +
                creatorAmount;
        }

        // Transfer Token
        _transfer(oldOwner, newOwner, _tokenId);

        // Transfer Payment
        if (ownerAmount > 0) {
            payable(oldOwner).sendValue(ownerAmount, _gasLimit);
        }

        emit ParticlonSold(
            _tokenId,
            oldOwner,
            newOwner,
            salePrice,
            royaltiesReceiver,
            creatorAmount
        );

        _refundOverpayment(salePrice, _gasLimit);

        // Andy was here
        // Signal to Universe Controller
        if (address(_universe) != address(0)) {
            _universe.onProtonSale(
                contractAddress,
                tokenId,
                oldOwner,
                newOwner,
                salePrice,
                royaltiesReceiver,
                creatorAmount
            );
        }
    }

    /**
     * @dev Pays out the Creator Royalties of the calling account
     * @param receiver  The receiver of the claimable royalties
     * @return          The amount of Creator Royalties claimed
     */
    function _claimCreatorRoyalties(address receiver)
        internal
        virtual
        returns (uint256)
    {
        uint256 claimableAmount = _tokenCreatorClaimableRoyalties[receiver];
        require(claimableAmount > 0, "PRT:E-411");

        delete _tokenCreatorClaimableRoyalties[receiver];
        payable(receiver).sendValue(claimableAmount, 0);

        emit RoyaltiesClaimed(receiver, claimableAmount);

        // Andy was here
        return claimableAmount;
    }

    function _refundOverpayment(uint256 threshold, uint256 gasLimit)
        internal
        virtual
    {
        // Andy was here, removed SafeMath
        uint256 overage = msg.value - threshold;
        if (overage > 0) {
            payable(_msgSender()).sendValue(overage, gasLimit);
        }
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        // Unlock NFT
        _tokenSalePrice[tokenId] = 0; // Andy was here
        _chargedState.setTemporaryLock(address(this), tokenId, false);

        super._transfer(from, to, tokenId);
    }

    /***********************************|
    |          GSN/MetaTx Relay         |
    |__________________________________*/

    /// @dev See {BaseRelayRecipient-_msgSender}.
    /// Andy: removed payable
    function _msgSender()
        internal
        view
        virtual
        override(BaseRelayRecipient, Context)
        returns (address)
    {
        return BaseRelayRecipient._msgSender();
    }

    /// @dev See {BaseRelayRecipient-_msgData}.
    function _msgData()
        internal
        view
        virtual
        override(BaseRelayRecipient, Context)
        returns (bytes memory)
    {
        return BaseRelayRecipient._msgData();
    }

    /***********************************|
    |             Modifiers             |
    |__________________________________*/

    // Andy was here
    modifier whenMintPhase(EMintPhase _mintPhase) {
        require(mintPhase == _mintPhase, "MINT PHASE ERR");
        _;
    }

    modifier whenNotPaused() {
        require(!_paused, "PRT:E-101");
        _;
    }

    modifier whenRemainingSupply() {
        _; // runs the function first
        require(totalSupply <= MAX_SUPPLY, "SUPPLY LIMIT");
    }

    modifier handlePayment(uint256 amount) {
        uint256 threshold = amount * PRICE;
        require(msg.value >= threshold, "LOW ETH");
        _refundOverpayment(threshold, 21000); // TODO check gasLimit
        _;
    }

    modifier onlyTokenOwnerOrApproved(uint256 tokenId) {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "PRT:E-105");
        _;
    }

    modifier onlyTokenCreator(uint256 tokenId) {
        require(_tokenCreator[tokenId] == _msgSender(), "PRT:E-104");
        _;
    }
}
