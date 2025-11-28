// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title AuctionMessaging
 * @dev A contract where message delivery slots are auctioned to highest bidders
 * @author Swift v2 Team
 */
contract AuctionMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed recipient,
        uint256 startingBid,
        uint256 endTime,
        uint256 timestamp
    );

    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 bidAmount,
        uint256 timestamp
    );

    event AuctionEnded(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 winningBid,
        uint256 timestamp
    );

    event MessageDelivered(
        uint256 indexed auctionId,
        address indexed sender,
        address indexed recipient,
        string content,
        uint256 timestamp
    );

    // Structs
    struct MessageAuction {
        uint256 id;
        address recipient;
        uint256 startingBid;
        uint256 currentBid;
        address currentBidder;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        bool isEnded;
        bool messageDelivered;
        string deliveredContent;
    }

    // State variables
    Counters.Counter private _auctionIdCounter;
    mapping(uint256 => MessageAuction) public messageAuctions;
    mapping(address => uint256[]) public recipientAuctions;
    mapping(address => uint256[]) public bidderAuctions;
    mapping(uint256 => mapping(address => uint256)) public bids; // auctionId => bidder => amount

    // Constants
    uint256 public constant AUCTION_CREATION_FEE = 0.000005 ether;
    uint256 public constant MIN_AUCTION_DURATION = 3600; // 1 hour
    uint256 public constant MAX_AUCTION_DURATION = 604800; // 7 days
    uint256 public constant MIN_BID_INCREMENT = 0.00001 ether;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;

    constructor() {
        _auctionIdCounter.increment();
    }

    /**
     * @dev Create a message delivery auction
     * @param _startingBid Minimum bid amount
     * @param _duration Auction duration in seconds
     */
    function createAuction(
        uint256 _startingBid,
        uint256 _duration
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= AUCTION_CREATION_FEE, "Insufficient fee");
        require(_startingBid > 0, "Starting bid must be greater than 0");
        require(_duration >= MIN_AUCTION_DURATION, "Duration too short");
        require(_duration <= MAX_AUCTION_DURATION, "Duration too long");
        
        uint256 auctionId = _auctionIdCounter.current();
        _auctionIdCounter.increment();

        uint256 endTime = block.timestamp + _duration;

        MessageAuction storage auction = messageAuctions[auctionId];
        auction.id = auctionId;
        auction.recipient = msg.sender;
        auction.startingBid = _startingBid;
        auction.currentBid = 0;
        auction.startTime = block.timestamp;
        auction.endTime = endTime;
        auction.isActive = true;
        auction.isEnded = false;
        auction.messageDelivered = false;

        recipientAuctions[msg.sender].push(auctionId);

        emit AuctionCreated(
            auctionId,
            msg.sender,
            _startingBid,
            endTime,
            block.timestamp
        );
    }

    /**
     * @dev Place a bid on an auction
     * @param _auctionId ID of the auction
     */
    function placeBid(uint256 _auctionId) 
        external 
        payable 
        nonReentrant 
    {
        MessageAuction storage auction = messageAuctions[_auctionId];
        require(auction.isActive, "Auction not active");
        require(block.timestamp < auction.endTime, "Auction ended");
        require(msg.sender != auction.recipient, "Cannot bid on own auction");
        
        uint256 minBid = auction.currentBid > 0 
            ? auction.currentBid + MIN_BID_INCREMENT 
            : auction.startingBid;
        require(msg.value >= minBid, "Bid too low");

        // Refund previous bidder
        if (auction.currentBidder != address(0)) {
            uint256 refundAmount = auction.currentBid;
            (bool success, ) = payable(auction.currentBidder).call{value: refundAmount}("");
            require(success, "Refund failed");
        }

        auction.currentBid = msg.value;
        auction.currentBidder = msg.sender;
        bids[_auctionId][msg.sender] = msg.value;

        bidderAuctions[msg.sender].push(_auctionId);

        emit BidPlaced(_auctionId, msg.sender, msg.value, block.timestamp);
    }

    /**
     * @dev End an auction
     * @param _auctionId ID of the auction
     */
    function endAuction(uint256 _auctionId) 
        external 
        nonReentrant 
    {
        MessageAuction storage auction = messageAuctions[_auctionId];
        require(auction.isActive, "Auction not active");
        require(block.timestamp >= auction.endTime, "Auction not ended yet");
        require(!auction.isEnded, "Already ended");

        auction.isActive = false;
        auction.isEnded = true;

        if (auction.currentBidder != address(0)) {
            // Transfer winning bid to recipient
            (bool success, ) = payable(auction.recipient).call{value: auction.currentBid}("");
            require(success, "Payment failed");

            emit AuctionEnded(
                _auctionId,
                auction.currentBidder,
                auction.currentBid,
                block.timestamp
            );
        } else {
            emit AuctionEnded(_auctionId, address(0), 0, block.timestamp);
        }
    }

    /**
     * @dev Deliver message after winning auction
     * @param _auctionId ID of the auction
     * @param _content Message content
     */
    function deliverMessage(uint256 _auctionId, string memory _content) 
        external 
        nonReentrant 
    {
        MessageAuction storage auction = messageAuctions[_auctionId];
        require(auction.isEnded, "Auction not ended");
        require(auction.currentBidder == msg.sender, "Only winner can deliver");
        require(!auction.messageDelivered, "Message already delivered");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");

        auction.messageDelivered = true;
        auction.deliveredContent = _content;

        emit MessageDelivered(
            _auctionId,
            msg.sender,
            auction.recipient,
            _content,
            block.timestamp
        );
    }

    /**
     * @dev Get auction details
     */
    function getAuction(uint256 _auctionId) 
        external 
        view 
        returns (
            uint256 id,
            address recipient,
            uint256 startingBid,
            uint256 currentBid,
            address currentBidder,
            uint256 startTime,
            uint256 endTime,
            bool isActive,
            bool isEnded,
            bool messageDelivered
        )
    {
        MessageAuction storage auction = messageAuctions[_auctionId];
        return (
            auction.id,
            auction.recipient,
            auction.startingBid,
            auction.currentBid,
            auction.currentBidder,
            auction.startTime,
            auction.endTime,
            auction.isActive,
            auction.isEnded,
            auction.messageDelivered
        );
    }

    /**
     * @dev Get delivered message content
     */
    function getDeliveredMessage(uint256 _auctionId) 
        external 
        view 
        returns (string memory)
    {
        MessageAuction storage auction = messageAuctions[_auctionId];
        require(
            msg.sender == auction.recipient || msg.sender == auction.currentBidder,
            "Not authorized"
        );
        require(auction.messageDelivered, "Message not delivered");
        
        return auction.deliveredContent;
    }

    /**
     * @dev Get recipient's auctions
     */
    function getRecipientAuctions(address _recipient) external view returns (uint256[] memory) {
        return recipientAuctions[_recipient];
    }

    /**
     * @dev Get bidder's auctions
     */
    function getBidderAuctions(address _bidder) external view returns (uint256[] memory) {
        return bidderAuctions[_bidder];
    }

    /**
     * @dev Withdraw contract balance (only owner)
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdraw failed");
    }
}
