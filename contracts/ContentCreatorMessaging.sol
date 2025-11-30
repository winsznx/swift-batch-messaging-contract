// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title ContentCreatorMessaging
 * @dev Monetized content platform with subscriptions and exclusive messaging
 * @author Swift v2 Team
 */
contract ContentCreatorMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event CreatorRegistered(
        address indexed creator,
        string name,
        uint256 timestamp
    );

    event SubscriptionCreated(
        uint256 indexed subscriptionId,
        address indexed subscriber,
        address indexed creator,
        uint256 timestamp
    );

    event ContentPublished(
        uint256 indexed contentId,
        address indexed creator,
        uint256 timestamp
    );

    event TipSent(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 timestamp
    );

    event ExclusiveMessageSent(
        uint256 indexed messageId,
        address indexed creator,
        uint256 timestamp
    );

    // Enums
    enum SubscriptionTier { Free, Basic, Premium, VIP }
    enum ContentType { Text, Image, Video, Audio }

    // Structs
    struct Creator {
        address wallet;
        string name;
        string bio;
        uint256 subscriberCount;
        uint256 totalEarned;
        uint256 contentCount;
        uint256 basicTierPrice;
        uint256 premiumTierPrice;
        uint256 vipTierPrice;
        bool isVerified;
        uint256 registeredAt;
    }

    struct Subscription {
        uint256 id;
        address subscriber;
        address creator;
        SubscriptionTier tier;
        uint256 subscribedAt;
        uint256 expiresAt;
        bool isActive;
        bool autoRenew;
    }

    struct Content {
        uint256 id;
        address creator;
        string title;
        string description;
        ContentType contentType;
        string contentHash;
        SubscriptionTier minTier;
        uint256 publishedAt;
        uint256 viewCount;
        uint256 likeCount;
        bool isExclusive;
    }

    struct ExclusiveMessage {
        uint256 id;
        address creator;
        address[] recipients;
        string content;
        SubscriptionTier minTier;
        uint256 timestamp;
    }

    // State variables
    Counters.Counter private _subscriptionIdCounter;
    Counters.Counter private _contentIdCounter;
    Counters.Counter private _messageIdCounter;
    
    mapping(address => Creator) public creators;
    mapping(uint256 => Subscription) public subscriptions;
    mapping(uint256 => Content) public contents;
    mapping(uint256 => ExclusiveMessage) public exclusiveMessages;
    mapping(address => mapping(address => uint256)) public activeSubscription;
    mapping(address => uint256[]) public creatorContent;
    mapping(address => uint256[]) public userSubscriptions;
    mapping(uint256 => mapping(address => bool)) public hasLiked;
    mapping(uint256 => mapping(address => bool)) public hasViewed;

    // Constants
    uint256 public constant MIN_TIER_PRICE = 0.001 ether;
    uint256 public constant SUBSCRIPTION_DURATION = 30 days;
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 5;
    uint256 public constant MAX_BIO_LENGTH = 500;
    uint256 public constant MAX_DESCRIPTION_LENGTH = 1000;

    constructor() {
        _subscriptionIdCounter.increment();
        _contentIdCounter.increment();
        _messageIdCounter.increment();
    }

    /**
     * @dev Register as content creator
     */
    function registerCreator(
        string memory _name,
        string memory _bio,
        uint256 _basicPrice,
        uint256 _premiumPrice,
        uint256 _vipPrice
    ) 
        external 
        nonReentrant 
    {
        require(creators[msg.sender].registeredAt == 0, "Already registered");
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_bio).length <= MAX_BIO_LENGTH, "Bio too long");
        require(_basicPrice >= MIN_TIER_PRICE, "Basic price too low");
        require(_premiumPrice >= _basicPrice, "Premium must be higher");
        require(_vipPrice >= _premiumPrice, "VIP must be highest");

        creators[msg.sender] = Creator({
            wallet: msg.sender,
            name: _name,
            bio: _bio,
            subscriberCount: 0,
            totalEarned: 0,
            contentCount: 0,
            basicTierPrice: _basicPrice,
            premiumTierPrice: _premiumPrice,
            vipTierPrice: _vipPrice,
            isVerified: false,
            registeredAt: block.timestamp
        });

        emit CreatorRegistered(msg.sender, _name, block.timestamp);
    }

    /**
     * @dev Subscribe to creator
     */
    function subscribe(
        address _creator,
        SubscriptionTier _tier,
        bool _autoRenew
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        require(creators[_creator].registeredAt != 0, "Creator not registered");
        require(_tier != SubscriptionTier.Free, "Cannot pay for free tier");
        require(
            activeSubscription[msg.sender][_creator] == 0,
            "Already subscribed"
        );

        uint256 price;
        if (_tier == SubscriptionTier.Basic) {
            price = creators[_creator].basicTierPrice;
        } else if (_tier == SubscriptionTier.Premium) {
            price = creators[_creator].premiumTierPrice;
        } else if (_tier == SubscriptionTier.VIP) {
            price = creators[_creator].vipTierPrice;
        }

        require(msg.value >= price, "Insufficient payment");

        uint256 subscriptionId = _subscriptionIdCounter.current();
        _subscriptionIdCounter.increment();

        subscriptions[subscriptionId] = Subscription({
            id: subscriptionId,
            subscriber: msg.sender,
            creator: _creator,
            tier: _tier,
            subscribedAt: block.timestamp,
            expiresAt: block.timestamp + SUBSCRIPTION_DURATION,
            isActive: true,
            autoRenew: _autoRenew
        });

        activeSubscription[msg.sender][_creator] = subscriptionId;
        userSubscriptions[msg.sender].push(subscriptionId);
        
        creators[_creator].subscriberCount++;

        // Transfer payment to creator
        uint256 platformFee = (price * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 creatorPayment = price - platformFee;

        creators[_creator].totalEarned += creatorPayment;

        (bool success, ) = payable(_creator).call{value: creatorPayment}("");
        require(success, "Payment failed");

        emit SubscriptionCreated(subscriptionId, msg.sender, _creator, block.timestamp);

        return subscriptionId;
    }

    /**
     * @dev Publish new content
     */
    function publishContent(
        string memory _title,
        string memory _description,
        ContentType _contentType,
        string memory _contentHash,
        SubscriptionTier _minTier,
        bool _isExclusive
    ) 
        external 
        nonReentrant 
        returns (uint256)
    {
        require(creators[msg.sender].registeredAt != 0, "Not a creator");
        require(bytes(_title).length > 0, "Title cannot be empty");
        require(bytes(_description).length <= MAX_DESCRIPTION_LENGTH, "Description too long");
        require(bytes(_contentHash).length > 0, "Content hash required");

        uint256 contentId = _contentIdCounter.current();
        _contentIdCounter.increment();

        contents[contentId] = Content({
            id: contentId,
            creator: msg.sender,
            title: _title,
            description: _description,
            contentType: _contentType,
            contentHash: _contentHash,
            minTier: _minTier,
            publishedAt: block.timestamp,
            viewCount: 0,
            likeCount: 0,
            isExclusive: _isExclusive
        });

        creatorContent[msg.sender].push(contentId);
        creators[msg.sender].contentCount++;

        emit ContentPublished(contentId, msg.sender, block.timestamp);

        return contentId;
    }

    /**
     * @dev Send exclusive message to subscribers
     */
    function sendExclusiveMessage(
        string memory _content,
        SubscriptionTier _minTier,
        address[] memory _specificRecipients
    ) 
        external 
        nonReentrant 
        returns (uint256)
    {
        require(creators[msg.sender].registeredAt != 0, "Not a creator");
        require(bytes(_content).length > 0, "Empty content");

        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        exclusiveMessages[messageId] = ExclusiveMessage({
            id: messageId,
            creator: msg.sender,
            recipients: _specificRecipients,
            content: _content,
            minTier: _minTier,
            timestamp: block.timestamp
        });

        emit ExclusiveMessageSent(messageId, msg.sender, block.timestamp);

        return messageId;
    }

    /**
     * @dev Send tip to creator
     */
    function sendTip(address _creator) 
        external 
        payable 
        nonReentrant 
    {
        require(creators[_creator].registeredAt != 0, "Creator not registered");
        require(msg.value > 0, "Tip amount must be > 0");

        uint256 platformFee = (msg.value * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 creatorAmount = msg.value - platformFee;

        creators[_creator].totalEarned += creatorAmount;

        (bool success, ) = payable(_creator).call{value: creatorAmount}("");
        require(success, "Tip failed");

        emit TipSent(msg.sender, _creator, creatorAmount, block.timestamp);
    }

    /**
     * @dev Like content
     */
    function likeContent(uint256 _contentId) 
        external 
        nonReentrant 
    {
        Content storage content = contents[_contentId];
        require(content.id != 0, "Content doesn't exist");
        require(!hasLiked[_contentId][msg.sender], "Already liked");

        // Check subscription tier access
        require(
            _hasAccess(msg.sender, content.creator, content.minTier),
            "Insufficient subscription tier"
        );

        hasLiked[_contentId][msg.sender] = true;
        content.likeCount++;
    }

    /**
     * @dev View content
     */
    function viewContent(uint256 _contentId) 
        external 
        nonReentrant 
    {
        Content storage content = contents[_contentId];
        require(content.id != 0, "Content doesn't exist");
        
        // Check subscription tier access
        require(
            _hasAccess(msg.sender, content.creator, content.minTier),
            "Insufficient subscription tier"
        );

        if (!hasViewed[_contentId][msg.sender]) {
            hasViewed[_contentId][msg.sender] = true;
            content.viewCount++;
        }
    }

    /**
     * @dev Check if user has access to content tier
     */
    function _hasAccess(
        address _user,
        address _creator,
        SubscriptionTier _requiredTier
    ) 
        private 
        view 
        returns (bool) 
    {
        if (_requiredTier == SubscriptionTier.Free) {
            return true;
        }

        uint256 subId = activeSubscription[_user][_creator];
        if (subId == 0) {
            return false;
        }

        Subscription memory sub = subscriptions[subId];
        if (!sub.isActive || block.timestamp > sub.expiresAt) {
            return false;
        }

        return uint8(sub.tier) >= uint8(_requiredTier);
    }

    /**
     * @dev Cancel subscription
     */
    function cancelSubscription(address _creator) 
        external 
        nonReentrant 
    {
        uint256 subId = activeSubscription[msg.sender][_creator];
        require(subId != 0, "No active subscription");

        Subscription storage sub = subscriptions[subId];
        sub.autoRenew = false;
    }

    /**
     * @dev Update creator pricing
     */
    function updatePricing(
        uint256 _basicPrice,
        uint256 _premiumPrice,
        uint256 _vipPrice
    ) 
        external 
    {
        require(creators[msg.sender].registeredAt != 0, "Not a creator");
        require(_basicPrice >= MIN_TIER_PRICE, "Basic price too low");
        require(_premiumPrice >= _basicPrice, "Premium must be higher");
        require(_vipPrice >= _premiumPrice, "VIP must be highest");

        creators[msg.sender].basicTierPrice = _basicPrice;
        creators[msg.sender].premiumTierPrice = _premiumPrice;
        creators[msg.sender].vipTierPrice = _vipPrice;
    }

    /**
     * @dev Get creator info
     */
    function getCreator(address _creator) 
        external 
        view 
        returns (
            string memory name,
            string memory bio,
            uint256 subscriberCount,
            uint256 contentCount,
            uint256 basicPrice,
            uint256 premiumPrice,
            uint256 vipPrice
        )
    {
        Creator memory creator = creators[_creator];
        return (
            creator.name,
            creator.bio,
            creator.subscriberCount,
            creator.contentCount,
            creator.basicTierPrice,
            creator.premiumTierPrice,
            creator.vipTierPrice
        );
    }

    /**
     * @dev Get creator's content
     */
    function getCreatorContent(address _creator) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return creatorContent[_creator];
    }

    /**
     * @dev Check subscription status
     */
    function hasActiveSubscription(address _user, address _creator) 
        external 
        view 
        returns (bool, SubscriptionTier) 
    {
        uint256 subId = activeSubscription[_user][_creator];
        if (subId == 0) {
            return (false, SubscriptionTier.Free);
        }

        Subscription memory sub = subscriptions[subId];
        if (!sub.isActive || block.timestamp > sub.expiresAt) {
            return (false, SubscriptionTier.Free);
        }

        return (true, sub.tier);
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
