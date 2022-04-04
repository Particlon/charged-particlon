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
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IParticlon.sol";
import "./interfaces/IChargedState.sol";
import "./interfaces/IChargedParticles.sol";
import "./interfaces/IERC721Consumable.sol";
import "./interfaces/ISignatureVerifier.sol";

import "./lib/ERC721A.sol";
import "./lib/TokenInfo.sol";
import "./lib/BlackholePrevention.sol";
import "./lib/RelayRecipient.sol";

contract Particlon is
    IParticlon,
    ERC721A,
    IERC721Consumable,
    Ownable,
    Pausable,
    RelayRecipient,
    ReentrancyGuard,
    BlackholePrevention
{
    // using SafeMath for uint256; // not needed since solidity 0.8
    using TokenInfo for address payable;
    using Strings for uint256;

    /// @dev In case we want to revoke the consumer part
    bool internal _revokeConsumerOnTransfer;

    /// @notice Address used to generate cryptographic signatures for whitelisted addresses
    address internal _signer = 0xE8cF9826C7702411bb916c447D759E0E631d2e68;

    uint256 internal _nonceClaim = 69;
    uint256 internal _nonceWL = 420;

    uint256 public constant MAX_SUPPLY = 10069;
    uint256 public constant INITIAL_PRICE = 0.15 ether;

    uint256 internal constant PERCENTAGE_SCALE = 1e4; // 10000  (100%)
    uint256 internal constant MAX_ROYALTIES = 8e3; // 8000   (80%)

    // Charged Particles V1 mainnet

    IChargedState internal _chargedState =
        IChargedState(0xB29256073C63960daAa398f1227D0adBC574341C);
    // IChargedSettings internal _chargedSettings;
    IChargedParticles internal _chargedParticles =
        IChargedParticles(0xaB1a1410EA40930755C1330Cc0fB3367897C8c41);

    /// @notice This needs to be set using the setAssetToken in order to get approved
    address internal _assetToken;

    // This right here drops the size so it doesn't break the limitation
    // Enable optimization also has to be tured on!
    ISignatureVerifier internal constant _signatureVerifier =
        ISignatureVerifier(0x47a0915747565E8264296457b894068fe5CA9186);

    uint256 internal _mintPrice;

    string internal _baseUri =
        "ipfs://QmQrdG1cESrBenNUaTmxckFm4gJwgLdkqTGxNLuh4t5vo8/";

    // Mapping from token ID to consumer address
    mapping(uint256 => address) _tokenConsumers;

    mapping(uint256 => address) internal _tokenCreator;
    mapping(uint256 => uint256) internal _tokenCreatorRoyaltiesPct;
    mapping(uint256 => address) internal _tokenCreatorRoyaltiesRedirect;
    mapping(address => uint256) internal _tokenCreatorClaimableRoyalties;

    mapping(uint256 => uint256) internal _tokenSalePrice;
    mapping(uint256 => uint256) internal _tokenLastSellPrice;

    /// @notice Adhere to limits per whitelisted wallet for claim mint phase
    mapping(address => uint256) internal _mintPassMinted;

    /// @notice Adhere to limits per whitelisted wallet for whitelist mint phase
    mapping(address => uint256) internal _whitelistedAddressMinted;

    /// @notice set to CLOSED by default
    EMintPhase public mintPhase;

    /***********************************|
    |          Initialization           |
    |__________________________________*/

    constructor() ERC721A("Particlon", "PART") {
        _mintPrice = INITIAL_PRICE;
    }

    /***********************************|
    |              Public               |
    |__________________________________*/

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
        override(IERC165, ERC721A)
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
        nonReentrant
        whenNotPaused
        notBeforePhase(EMintPhase.PUBLIC)
        whenRemainingSupply
        requirePayment(amount)
        returns (bool)
    {
        // They may have minted 10, but if only 2 remain in supply, then they will only get 2, so only pay for 2
        uint256 actualPrice = _mintAmount(amount, _msgSender());
        _refundOverpayment(actualPrice, 0); // dont worry about gasLimit here as the "minter" could only hook themselves
        return true;
    }

    /// @notice Andy was here
    function mintWhitelist(
        uint256 amountMint,
        uint256 amountAllowed,
        uint256 nonce,
        bytes calldata signature
    )
        external
        payable
        override
        nonReentrant
        whenNotPaused
        notBeforePhase(EMintPhase.WHITELIST)
        whenRemainingSupply
        requirePayment(amountMint)
        requireWhitelist(amountMint, amountAllowed, nonce, signature)
        returns (bool)
    {
        // They may have been whitelisted to mint 10, but if only 2 remain in supply, then they will only get 2, so only pay for 2
        uint256 actualPrice = _mintAmount(amountMint, _msgSender());
        _refundOverpayment(actualPrice, 0);
        return true;
    }

    function mintFree(
        uint256 amountMint,
        uint256 amountAllowed,
        uint256 nonce,
        bytes calldata signature
    )
        external
        override
        whenNotPaused
        notBeforePhase(EMintPhase.CLAIM)
        whenRemainingSupply
        requirePass(amountMint, amountAllowed, nonce, signature)
        returns (bool)
    {
        // They may have been whitelisted to mint 10, but if only 2 remain in supply, then they will only get 2
        _mintAmount(amountMint, _msgSender());
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

    // Andy was here (Andy is everywhere)

    function setSignerAddress(address signer) external onlyOwner {
        _signer = signer;
        emit NewSignerAddress(signer);
    }

    // In case we need to "undo" a signature/prevent it from being used,
    // This is easier than changing the signer
    // we would also need to remake all unused signatures
    function setNonces(uint256 nonceClaim, uint256 nonceWL) external onlyOwner {
        _nonceClaim = nonceClaim;
        _nonceWL = nonceWL;
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

    /// @notice This is needed for the reveal
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

    function withdrawERC20(
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

    function _baseURI() internal view override returns (string memory) {
        return _baseUri;
    }

    function _mintAmount(uint256 amount, address creator)
        internal
        returns (uint256 actualPrice)
    {
        uint256 newTokenId = totalSupply();
        // newTokenId is equal to the supply at this stage
        if (newTokenId + amount > MAX_SUPPLY) {
            amount = MAX_SUPPLY - newTokenId;
        }
        // totalSupply += amount;

        // _safeMint's second argument now takes in a quantity, not a tokenId.
        _safeMint(creator, amount);
        actualPrice = amount * _mintPrice; // Charge people for the ACTUAL amount minted;

        uint256 assetAmount;
        newTokenId++;
        for (uint256 i; i < amount; i++) {
            // Set the first minters as the creators
            _tokenCreator[newTokenId + i] = creator;
            assetAmount += _getAssetAmount(newTokenId + i);
            // _chargeParticlon(newTokenId, "generic", assetAmount);
        }
        // Put all ERC20 tokens into the first Particlon to save a lot of gas
        _chargeParticlon(newTokenId, "generic", assetAmount);
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

    function _beforeTokenTransfers(
        address _from,
        address _to,
        uint256 _startTokenId,
        uint256 _quantity
    ) internal virtual override(ERC721A) {
        super._beforeTokenTransfers(_from, _to, _startTokenId, _quantity);

        require(!paused(), "ERC721Pausable: token transfer while paused");

        if (_revokeConsumerOnTransfer) {
            uint256 _tokenId = _startTokenId;
            for (uint256 i; i < _quantity; i++) {
                _changeConsumer(_from, address(0), _tokenId);
                _tokenId++;
            }
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

    /// @notice The tokens from a batch are being nested into the first NFT minted in that batch
    function _getAssetAmount(uint256 tokenId) internal pure returns (uint256) {
        if (tokenId == MAX_SUPPLY) {
            return 1596 * 10**18;
        } else if (tokenId > 9000) {
            return 1403 * 10**18;
        } else if (tokenId > 6000) {
            return 1000 * 10**18;
        } else if (tokenId > 3000) {
            return 1500 * 10**18;
        } else if (tokenId > 1000) {
            return 1750 * 10**18;
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

    /// @dev This is missing from ERC721A for some reason.
    function _isApprovedOrOwner(address spender, uint256 tokenId)
        internal
        view
        virtual
        returns (bool)
    {
        require(
            _exists(tokenId),
            "ERC721: operator query for nonexistent token"
        );
        address owner = ownerOf(tokenId);
        return (spender == owner ||
            isApprovedForAll(owner, spender) ||
            getApproved(tokenId) == spender);
    }

    /***********************************|
    |             Modifiers             |
    |__________________________________*/

    // Andy was here
    modifier notBeforePhase(EMintPhase _mintPhase) {
        require(mintPhase >= _mintPhase, "MINT PHASE ERR");
        _;
    }

    modifier whenRemainingSupply() {
        require(totalSupply() < MAX_SUPPLY, "SUPPLY LIMIT");
        _;
    }

    modifier requirePayment(uint256 amount) {
        uint256 fullPrice = amount * _mintPrice;
        require(msg.value >= fullPrice, "LOW ETH");
        _;
    }

    modifier requireWhitelist(
        uint256 amountMint,
        uint256 amountAllowed,
        uint256 nonce,
        bytes calldata signature
    ) {
        require(amountMint <= amountAllowed, "AMOUNT ERR");
        require(nonce == _nonceWL, "NONCE ERR");
        require(
            _signatureVerifier.verify(
                _signer,
                _msgSender(),
                amountAllowed,
                nonce, // prevent WL signatures being used for claiming
                signature
            ),
            "SIGNATURE ERR"
        );
        require(
            _whitelistedAddressMinted[_msgSender()] + amountMint <=
                amountAllowed,
            "CLAIM ERR"
        );
        _whitelistedAddressMinted[_msgSender()] += amountMint;
        _;
    }

    /// @notice A snapshot is taken before the mint (mint pass NFT count is taken into consideration)
    modifier requirePass(
        uint256 amountMint,
        uint256 amountAllowed,
        uint256 nonce,
        bytes calldata signature
    ) {
        require(amountMint <= amountAllowed, "AMOUNT ERR");
        require(nonce == _nonceClaim, "NONCE ERR");
        require(
            _signatureVerifier.verify(
                _signer,
                _msgSender(),
                amountAllowed,
                nonce,
                signature
            ),
            "SIGNATURE ERR"
        );
        require(
            _mintPassMinted[_msgSender()] + amountMint <= amountAllowed,
            "CLAIM ERR"
        );
        _mintPassMinted[_msgSender()] += amountMint;
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
