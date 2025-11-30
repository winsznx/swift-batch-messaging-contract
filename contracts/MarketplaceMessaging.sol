// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title MarketplaceMessaging
 * @dev P2P marketplace with escrow messaging and trade negotiations
 * @author Swift v2 Team
 */
contract MarketplaceMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event ListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        string title,
        uint256 price,
        uint256 timestamp
    );

    event OfferMade(
        uint256 indexed offerId,
        uint256 indexed listingId,
        address indexed buyer,
        uint256 amount,
        uint256 timestamp
    );

    event TradeStarted(
        uint256 indexed tradeId,
        uint256 indexed listingId,
        address indexed buyer,
        uint256 timestamp
    );

    event TradeCompleted(
        uint256 indexed tradeId,
        uint256 timestamp
    );

    event MessageSent(
        uint256 indexed messageId,
        uint256 indexed tradeId,
        address indexed sender,
        uint256 timestamp
    );

    // Enums
    enum ListingStatus { Active, Sold, Cancelled }
    enum TradeStatus { Pending, Accepted, Shipped, Delivered, Completed, Disputed, Cancelled }
    enum OfferStatus { Pending, Accepted, Rejected, Expired }

    // Structs
    struct Listing {
        uint256 id;
        address seller;
        string title;
        string description;
        string category;
        uint256 price;
        ListingStatus status;
        uint256 createdAt;
        string imageHash;
        bool isNegotiable;
    }

    struct Offer {
        uint256 id;
        uint256 listingId;
        address buyer;
        uint256 amount;
        string message;
        OfferStatus status;
        uint256 createdAt;
        uint256 expiresAt;
    }

    struct Trade {
        uint256 id;
        uint256 listingId;
        address seller;
        address buyer;
        uint256 amount;
        TradeStatus status;
        uint256 createdAt;
        uint256 completedAt;
        uint256 escrowAmount;
    }

    struct TradeMessage {
        uint256 id;
        uint256 tradeId;
        address sender;
        string content;
        uint256 timestamp;
        bool isSystemMessage;
    }

    struct Review {
        address reviewer;
        address reviewee;
        uint8 rating;
        string comment;
        uint256 timestamp;
    }

    // State variables
    Counters.Counter private _listingIdCounter;
    Counters.Counter private _offerIdCounter;
    Counters.Counter private _tradeIdCounter;
    Counters.Counter private _messageIdCounter;
    
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Offer) public offers;
    mapping(uint256 => Trade) public trades;
    mapping(uint256 => TradeMessage) public tradeMessages;
    mapping(uint256 => uint256[]) public listingOffers;
    mapping(uint256 => uint256[]) public tradeMessageList;
    mapping(address => uint256[]) public userListings;
    mapping(address => uint256[]) public userTrades;
    mapping(address => Review[]) public userReviews;
    mapping(address => uint256) public sellerRating;
    mapping(address => uint256) public totalRatings;

    // Constants
    uint256 public constant MAX_TITLE_LENGTH = 200;
    uint256 public constant MAX_DESCRIPTION_LENGTH = 2000;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant LISTING_FEE = 0.0001 ether;
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 3;
    uint256 public constant OFFER_DURATION = 7 days;

    constructor() {
        _listingIdCounter.increment();
        _offerIdCounter.increment();
        _tradeIdCounter.increment();
        _messageIdCounter.increment();
    }

    /**
     * @dev Create new listing
     */
    function createListing(
        string memory _title,
        string memory _description,
        string memory _category,
        uint256 _price,
        string memory _imageHash,
        bool _isNegotiable
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        require(msg.value >= LISTING_FEE, "Insufficient listing fee");
        require(bytes(_title).length > 0 && bytes(_title).length <= MAX_TITLE_LENGTH, "Invalid title");
        require(bytes(_description).length <= MAX_DESCRIPTION_LENGTH, "Description too long");
        require(_price > 0, "Price must be > 0");

        uint256 listingId = _listingIdCounter.current();
        _listingIdCounter.increment();

        listings[listingId] = Listing({
            id: listingId,
            seller: msg.sender,
            title: _title,
            description: _description,
            category: _category,
            price: _price,
            status: ListingStatus.Active,
            createdAt: block.timestamp,
            imageHash: _imageHash,
            isNegotiable: _isNegotiable
        });

        userListings[msg.sender].push(listingId);

        emit ListingCreated(listingId, msg.sender, _title, _price, block.timestamp);

        return listingId;
    }

    /**
     * @dev Make offer on listing
     */
    function makeOffer(
        uint256 _listingId,
        uint256 _amount,
        string memory _message
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        Listing storage listing = listings[_listingId];
        require(listing.status == ListingStatus.Active, "Listing not active");
        require(listing.seller != msg.sender, "Cannot offer on own listing");
        require(_amount > 0, "Amount must be > 0");
        
        if (!listing.isNegotiable) {
            require(_amount >= listing.price, "Must match listing price");
        }

        require(msg.value >= _amount, "Insufficient payment");

        uint256 offerId = _offerIdCounter.current();
        _offerIdCounter.increment();

        offers[offerId] = Offer({
            id: offerId,
            listingId: _listingId,
            buyer: msg.sender,
            amount: _amount,
            message: _message,
            status: OfferStatus.Pending,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + OFFER_DURATION
        });

        listingOffers[_listingId].push(offerId);

        emit OfferMade(offerId, _listingId, msg.sender, _amount, block.timestamp);

        return offerId;
    }

    /**
     * @dev Accept offer and start trade
     */
    function acceptOffer(uint256 _offerId) 
        external 
        nonReentrant 
        returns (uint256)
    {
        Offer storage offer = offers[_offerId];
        Listing storage listing = listings[offer.listingId];
        
        require(listing.seller == msg.sender, "Only seller can accept");
        require(offer.status == OfferStatus.Pending, "Offer not pending");
        require(block.timestamp < offer.expiresAt, "Offer expired");

        offer.status = OfferStatus.Accepted;
        listing.status = ListingStatus.Sold;

        uint256 tradeId = _tradeIdCounter.current();
        _tradeIdCounter.increment();

        trades[tradeId] = Trade({
            id: tradeId,
            listingId: offer.listingId,
            seller: listing.seller,
            buyer: offer.buyer,
            amount: offer.amount,
            status: TradeStatus.Accepted,
            createdAt: block.timestamp,
            completedAt: 0,
            escrowAmount: offer.amount
        });

        userTrades[listing.seller].push(tradeId);
        userTrades[offer.buyer].push(tradeId);

        emit TradeStarted(tradeId, offer.listingId, offer.buyer, block.timestamp);

        return tradeId;
    }

    /**
     * @dev Send trade message
     */
    function sendTradeMessage(
        uint256 _tradeId,
        string memory _content
    ) 
        external 
        nonReentrant 
        returns (uint256)
    {
        Trade storage trade = trades[_tradeId];
        require(
            trade.seller == msg.sender || trade.buyer == msg.sender,
            "Not trade participant"
        );
        require(trade.status != TradeStatus.Completed, "Trade completed");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");

        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        tradeMessages[messageId] = TradeMessage({
            id: messageId,
            tradeId: _tradeId,
            sender: msg.sender,
            content: _content,
            timestamp: block.timestamp,
            isSystemMessage: false
        });

        tradeMessageList[_tradeId].push(messageId);

        emit MessageSent(messageId, _tradeId, msg.sender, block.timestamp);

        return messageId;
    }

    /**
     * @dev Mark item as shipped
     */
    function markShipped(uint256 _tradeId) 
        external 
        nonReentrant 
    {
        Trade storage trade = trades[_tradeId];
        require(trade.seller == msg.sender, "Only seller can mark shipped");
        require(trade.status == TradeStatus.Accepted, "Invalid trade status");

        trade.status = TradeStatus.Shipped;

        _sendSystemMessage(_tradeId, "Item has been marked as shipped");
    }

    /**
     * @dev Confirm delivery
     */
    function confirmDelivery(uint256 _tradeId) 
        external 
        nonReentrant 
    {
        Trade storage trade = trades[_tradeId];
        require(trade.buyer == msg.sender, "Only buyer can confirm");
        require(trade.status == TradeStatus.Shipped, "Item not shipped");

        trade.status = TradeStatus.Delivered;

        _sendSystemMessage(_tradeId, "Delivery confirmed by buyer");
    }

    /**
     * @dev Complete trade and release escrow
     */
    function completeTrade(uint256 _tradeId) 
        external 
        nonReentrant 
    {
        Trade storage trade = trades[_tradeId];
        require(trade.buyer == msg.sender, "Only buyer can complete");
        require(trade.status == TradeStatus.Delivered, "Not delivered");

        trade.status = TradeStatus.Completed;
        trade.completedAt = block.timestamp;

        uint256 platformFee = (trade.escrowAmount * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 sellerPayment = trade.escrowAmount - platformFee;

        trade.escrowAmount = 0;

        (bool success, ) = payable(trade.seller).call{value: sellerPayment}("");
        require(success, "Payment failed");

        _sendSystemMessage(_tradeId, "Trade completed successfully");

        emit TradeCompleted(_tradeId, block.timestamp);
    }

    /**
     * @dev Leave review
     */
    function leaveReview(
        uint256 _tradeId,
        uint8 _rating,
        string memory _comment
    ) 
        external 
        nonReentrant 
    {
        Trade storage trade = trades[_tradeId];
        require(trade.status == TradeStatus.Completed, "Trade not completed");
        require(_rating >= 1 && _rating <= 5, "Rating must be 1-5");
        
        address reviewee;
        if (msg.sender == trade.buyer) {
            reviewee = trade.seller;
        } else if (msg.sender == trade.seller) {
            reviewee = trade.buyer;
        } else {
            revert("Not trade participant");
        }

        userReviews[reviewee].push(Review({
            reviewer: msg.sender,
            reviewee: reviewee,
            rating: _rating,
            comment: _comment,
            timestamp: block.timestamp
        }));

        // Update rating
        uint256 totalScore = sellerRating[reviewee] * totalRatings[reviewee];
        totalRatings[reviewee]++;
        sellerRating[reviewee] = (totalScore + _rating) / totalRatings[reviewee];
    }

    /**
     * @dev Send system message
     */
    function _sendSystemMessage(uint256 _tradeId, string memory _content) 
        private 
    {
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        tradeMessages[messageId] = TradeMessage({
            id: messageId,
            tradeId: _tradeId,
            sender: address(0),
            content: _content,
            timestamp: block.timestamp,
            isSystemMessage: true
        });

        tradeMessageList[_tradeId].push(messageId);
    }

    /**
     * @dev Cancel listing
     */
    function cancelListing(uint256 _listingId) 
        external 
        nonReentrant 
    {
        Listing storage listing = listings[_listingId];
        require(listing.seller == msg.sender, "Only seller can cancel");
        require(listing.status == ListingStatus.Active, "Listing not active");

        listing.status = ListingStatus.Cancelled;
    }

    /**
     * @dev Cancel offer and refund
     */
    function cancelOffer(uint256 _offerId) 
        external 
        nonReentrant 
    {
        Offer storage offer = offers[_offerId];
        require(offer.buyer == msg.sender, "Only buyer can cancel");
        require(offer.status == OfferStatus.Pending, "Offer not pending");

        offer.status = OfferStatus.Rejected;

        (bool success, ) = payable(msg.sender).call{value: offer.amount}("");
        require(success, "Refund failed");
    }

    /**
     * @dev Get listing details
     */
    function getListing(uint256 _listingId) 
        external 
        view 
        returns (
            uint256 id,
            address seller,
            string memory title,
            string memory category,
            uint256 price,
            ListingStatus status,
            bool isNegotiable
        )
    {
        Listing memory listing = listings[_listingId];
        return (
            listing.id,
            listing.seller,
            listing.title,
            listing.category,
            listing.price,
            listing.status,
            listing.isNegotiable
        );
    }

    /**
     * @dev Get trade messages
     */
    function getTradeMessages(uint256 _tradeId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return tradeMessageList[_tradeId];
    }

    /**
     * @dev Get user reviews
     */
    function getUserReviews(address _user) 
        external 
        view 
        returns (Review[] memory) 
    {
        return userReviews[_user];
    }

    /**
     * @dev Get seller rating
     */
    function getSellerRating(address _seller) 
        external 
        view 
        returns (uint256 rating, uint256 totalReviews) 
    {
        return (sellerRating[_seller], totalRatings[_seller]);
    }

    /**
     * @dev Withdraw platform fees (only owner)
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdraw failed");
    }
}
