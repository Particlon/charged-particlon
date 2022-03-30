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

// import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
// import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IParticlon.sol";
import "./interfaces/IChargedState.sol";
import "./interfaces/IChargedSettings.sol";
import "./interfaces/IChargedParticles.sol";
import "./interfaces/IERC721Consumable.sol";
import "./interfaces/ISignatureVerifier.sol";

import "./lib/TokenInfo.sol";
import "./lib/BlackholePrevention.sol";
import "./lib/RelayRecipient.sol";

contract Particlon is
    IParticlon,
    ERC721Pausable,
    IERC721Consumable,
    Ownable,
    RelayRecipient,
    ReentrancyGuard,
    BlackholePrevention
{
    // using SafeMath for uint256; // not needed since solidity 0.8
    using TokenInfo for address payable;
    using Strings for uint256;
    // using Counters for Counters.Counter;

    bool internal _revokeConsumerOnTransfer;
    address internal _signer;

    /// @notice Using the same naming convention to denote current supply as ERC721Enumerable
    uint256 public totalSupply;
    uint256 public constant MAX_SUPPLY = 10069;
    uint256 public constant INITIAL_PRICE = 0.15 ether;

    uint256 internal constant PERCENTAGE_SCALE = 1e4; // 10000  (100%)
    uint256 internal constant MAX_ROYALTIES = 8e3; // 8000   (80%)

    IChargedState internal _chargedState;
    // IChargedSettings internal _chargedSettings;
    IChargedParticles internal _chargedParticles;

    address internal _assetToken;
    ISignatureVerifier internal immutable _signatureVerifier; // This right here drops the size from 29kb to 15kb

    // Counters.Counter internal _tokenIds;

    uint256 internal _mintPrice;

    string internal _baseUri;

    // Mapping from token ID to consumer address
    mapping(uint256 => address) _tokenConsumers;

    mapping(uint256 => address) internal _tokenCreator;
    mapping(uint256 => uint256) internal _tokenCreatorRoyaltiesPct;
    mapping(uint256 => address) internal _tokenCreatorRoyaltiesRedirect;
    mapping(address => uint256) internal _tokenCreatorClaimableRoyalties;

    mapping(uint256 => uint256) internal _tokenSalePrice;
    mapping(uint256 => uint256) internal _tokenLastSellPrice;

    /// @notice Adhere to limits per whitelisted wallet for whitelist mint phase
    mapping(address => uint256) internal _whitelistedAddressMinted;
    mapping(address => uint256) internal _mintPassMinted;

    /// @notice Address used to generate cryptographic signatures for whitelisted addresses

    /// @notice set to CLOSED by default
    EMintPhase public mintPhase;

    /***********************************|
    |          Initialization           |
    |__________________________________*/

    constructor(address signatureVerifier) ERC721("Particlon", "PART") {
        _signatureVerifier = ISignatureVerifier(signatureVerifier);
        _mintPrice = INITIAL_PRICE;
    }

    /***********************************|
    |              Public               |
    |__________________________________*/

    function baseURI() external view override returns (string memory) {
        return _baseUri;
    }

    // Define an "onlyOwner" switch
    function setRevokeConsumerOnTransfer(bool state) external onlyOwner {
        _revokeConsumerOnTransfer = state;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(IERC165, ERC721)
        returns (bool)
    {
        return
            interfaceId == type(IERC721Consumable).interfaceId ||
            super.supportsInterface(interfaceId);
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
        override
        returns (address)
    {
        return _tokenCreator[tokenId];
    }

    function getSalePrice(uint256 tokenId)
        external
        view
        override
        returns (uint256)
    {
        return _tokenSalePrice[tokenId];
    }

    function getLastSellPrice(uint256 tokenId)
        external
        view
        override
        returns (uint256)
    {
        return _tokenLastSellPrice[tokenId];
    }

    function getCreatorRoyalties(address account)
        external
        view
        override
        returns (uint256)
    {
        return _tokenCreatorClaimableRoyalties[account];
    }

    function getCreatorRoyaltiesPct(uint256 tokenId)
        external
        view
        override
        returns (uint256)
    {
        return _tokenCreatorRoyaltiesPct[tokenId];
    }

    function getCreatorRoyaltiesReceiver(uint256 tokenId)
        external
        view
        override
        returns (address)
    {
        return _creatorRoyaltiesReceiver(tokenId);
    }

    function claimCreatorRoyalties()
        external
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
    function mint(uint256 amount)
        external
        payable
        override
        /// string[] calldata tokenMetaUris
        nonReentrant
        whenNotPaused
        whenMintPhase(EMintPhase.PUBLIC)
        whenRemainingSupply
        requirePayment(amount)
        returns (bool)
    {
        // They may have minted 10, but if only 2 remain in supply, then they will only get 2, so only pay for 2
        uint256 actualPrice = _mintAmount(amount);
        _refundOverpayment(actualPrice, 0); // dont worry about gasLimit here as the "minter" could only hook themselves
        return true;
    }

    /// @notice Andy was here
    function mintWhitelist(uint256 amount, bytes calldata signature)
        external
        payable
        override
        /// string[] calldata tokenMetaUris
        nonReentrant
        whenNotPaused
        whenMintPhase(EMintPhase.WHITELIST)
        whenRemainingSupply
        requirePayment(amount)
        requireWhitelist(amount, signature)
        returns (bool)
    {
        // They may have been whitelisted to mint 10, but if only 2 remain in supply, then they will only get 2, so only pay for 2
        uint256 actualPrice = _mintAmount(amount);
        _refundOverpayment(actualPrice, 0);
        return true;
    }

    function mintFree(uint256 amount, bytes calldata signature)
        external
        override
        /// string[] calldata tokenMetaUris
        whenNotPaused
        whenMintPhase(EMintPhase.CLAIM)
        whenRemainingSupply
        requirePass(amount, signature)
        returns (bool)
    {
        // They may have been whitelisted to mint 10, but if only 2 remain in supply, then they will only get 2
        _mintAmount(amount);
        return true;
    }

    /***********************************|
    |           Buy Particlons          |
    |__________________________________*/

    function buyParticlon(uint256 tokenId, uint256 gasLimit)
        external
        payable
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
        override
        whenNotPaused
        onlyTokenOwnerOrApproved(tokenId)
    {
        _setSalePrice(tokenId, salePrice);
    }

    function setRoyaltiesPct(uint256 tokenId, uint256 royaltiesPct)
        external
        override
        whenNotPaused
        onlyTokenCreator(tokenId)
        onlyTokenOwnerOrApproved(tokenId)
    {
        _setRoyaltiesPct(tokenId, royaltiesPct);
    }

    function setCreatorRoyaltiesReceiver(uint256 tokenId, address receiver)
        external
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
            _msgSender() == owner ||
                _msgSender() == getApproved(_tokenId) ||
                isApprovedForAll(owner, _msgSender()),
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
        _assetToken = assetToken;
        // Need to Approve Charged Particles to transfer Assets from Particlon
        IERC20(assetToken).approve(
            address(_chargedParticles),
            type(uint256).max
        );
        emit AssetTokenSet(assetToken);
    }

    function setMintPrice(uint256 price) external onlyOwner {
        _mintPrice = price;
        emit NewMintPrice(price);
    }

    /// @notice Andy was here
    function setURI(string memory uri) external onlyOwner {
        _baseUri = uri;
        emit NewBaseURI(uri);
    }

    function setMintPhase(EMintPhase _mintPhase) external onlyOwner {
        mintPhase = _mintPhase;
        emit NewMintPhase(_mintPhase);
    }

    function setPausedState(bool state) external onlyOwner {
        state ? _pause() : _unpause(); // these emit events
    }

    /**
     * @dev Setup the ChargedParticles Interface
     */
    function setChargedParticles(address chargedParticles) external onlyOwner {
        _chargedParticles = IChargedParticles(chargedParticles);
        emit ChargedParticlesSet(chargedParticles);
    }

    /// @dev Setup the Charged-State Controller
    function setChargedState(address stateController) external onlyOwner {
        _chargedState = IChargedState(stateController);
        emit ChargedStateSet(stateController);
    }

    /// @dev Setup the Charged-Settings Controller
    // function setChargedSettings(address settings) external onlyOwner {
    //     _chargedSettings = IChargedSettings(settings);
    //     emit ChargedSettingsSet(settings);
    // }

    function setTrustedForwarder(address _trustedForwarder) external onlyOwner {
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

    function _mintAmount(uint256 amount)
        internal
        returns (uint256 actualPrice)
    {
        uint256 newTokenId = totalSupply;
        if (totalSupply + amount > MAX_SUPPLY) {
            amount = MAX_SUPPLY - totalSupply;
        }
        totalSupply += amount;
        actualPrice = amount * _mintPrice; // Charge people for the ACTUAL amount minted;

        for (uint256 i; i < amount; i++) {
            _createChargedParticlon(++newTokenId, _msgSender());
        }
    }

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
    ) internal virtual override(ERC721Pausable) {
        super._beforeTokenTransfer(_from, _to, _tokenId);

        if (_revokeConsumerOnTransfer) {
            _changeConsumer(_from, address(0), _tokenId);
        }
    }

    function _setSalePrice(uint256 tokenId, uint256 salePrice) internal {
        _tokenSalePrice[tokenId] = salePrice;

        // Temp-Lock/Unlock NFT
        //  prevents front-running the sale and draining the value of the NFT just before sale
        _chargedState.setTemporaryLock(address(this), tokenId, (salePrice > 0));

        emit SalePriceSet(tokenId, salePrice);
    }

    function _setRoyaltiesPct(uint256 tokenId, uint256 royaltiesPct) internal {
        require(royaltiesPct <= MAX_ROYALTIES, "PRT:E-421"); // Andy was here
        _tokenCreatorRoyaltiesPct[tokenId] = royaltiesPct;
        emit CreatorRoyaltiesSet(tokenId, royaltiesPct);
    }

    function _creatorRoyaltiesReceiver(uint256 tokenId)
        internal
        view
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
    {
        _safeMint(creator, newTokenId, "");
        _tokenCreator[newTokenId] = creator;

        uint256 assetAmount = _getAssetAmount(newTokenId);
        _chargeParticlon(newTokenId, "generic", assetAmount);
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
        uint256 assetAmount
    ) internal {
        address _self = address(this);
        _chargedParticles.energizeParticle(
            _self,
            tokenId,
            walletManagerId,
            _assetToken,
            assetAmount,
            _self
        );
    }

    function _buyParticlon(uint256 _tokenId, uint256 _gasLimit)
        internal
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
        // creatorAmount;
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
            _tokenCreatorClaimableRoyalties[royaltiesReceiver] += creatorAmount;
        }

        // Transfer Token
        _transfer(oldOwner, newOwner, _tokenId);

        emit ParticlonSold(
            _tokenId,
            oldOwner,
            newOwner,
            salePrice,
            royaltiesReceiver,
            creatorAmount
        );

        // Transfer Payment
        if (ownerAmount > 0) {
            payable(oldOwner).sendValue(ownerAmount, _gasLimit);
        }
        _refundOverpayment(salePrice, _gasLimit);
    }

    /**
     * @dev Pays out the Creator Royalties of the calling account
     * @param receiver  The receiver of the claimable royalties
     * @return          The amount of Creator Royalties claimed
     */
    function _claimCreatorRoyalties(address receiver)
        internal
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

    function _refundOverpayment(uint256 threshold, uint256 gasLimit) internal {
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
    ) internal override {
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
        override(BaseRelayRecipient, Context)
        returns (address)
    {
        return BaseRelayRecipient._msgSender();
    }

    /// @dev See {BaseRelayRecipient-_msgData}.
    function _msgData()
        internal
        view
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

    modifier whenRemainingSupply() {
        require(totalSupply < MAX_SUPPLY, "SUPPLY LIMIT");
        _;
    }

    modifier requirePayment(uint256 amount) {
        uint256 fullPrice = amount * _mintPrice;
        require(msg.value >= fullPrice, "LOW ETH");
        _;
    }

    modifier requireWhitelist(uint256 amount, bytes calldata signature) {
        require(
            _signatureVerifier.verify(_signer, _msgSender(), amount, signature),
            "INVALID SIGNATURE"
        );
        require(
            _whitelistedAddressMinted[_msgSender()] < amount,
            "ALREADY CLAIMED WHITELIST"
        );
        _whitelistedAddressMinted[_msgSender()] += amount;
        _;
    }

    /// @notice A snapshot is taken before the mint (mint pass NFT count is taken into consideration)
    modifier requirePass(uint256 amount, bytes calldata signature) {
        require(
            _signatureVerifier.verify(_signer, _msgSender(), amount, signature),
            "INVALID SIGNATURE"
        );
        require(
            _mintPassMinted[_msgSender()] < amount,
            "ALREADY CLAIMED WHITELIST"
        );
        _mintPassMinted[_msgSender()] += amount;
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
