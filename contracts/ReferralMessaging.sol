// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title ReferralMessaging
 * @dev Messaging platform with multi-tier referral rewards and incentive system
 * @author Swift v2 Team
 */
contract ReferralMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event UserRegistered(
        address indexed user,
        address indexed referrer,
        uint256 timestamp
    );

    event MessageSent(
        uint256 indexed messageId,
        address indexed sender,
        address indexed recipient,
        uint256 timestamp
    );

    event ReferralRewardPaid(
        address indexed referrer,
        address indexed referred,
        uint256 amount,
        uint8 tier,
        uint256 timestamp
    );

    event MilestoneAchieved(
        address indexed user,
        uint256 milestone,
        uint256 reward,
        uint256 timestamp
    );

    // Structs
    struct User {
        address wallet;
        address referrer;
        uint256 registeredAt;
        uint256 totalReferred;
        uint256 directReferrals;
        uint256 totalEarned;
        uint256 messagesSent;
        bool isActive;
    }

    struct Message {
        uint256 id;
        address sender;
        address recipient;
        string content;
        uint256 timestamp;
        uint256 fee;
    }

    struct ReferralTier {
        uint8 tier;
        uint256 percentage;
        uint256 maxDepth;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(address => User) public users;
    mapping(uint256 => Message) public messages;
    mapping(address => uint256[]) public userMessages;
    mapping(address => address[]) public userReferrals;
    mapping(address => uint256) public pendingRewards;
    
    ReferralTier[] public referralTiers;
    uint256[] public milestoneTargets;
    uint256[] public milestoneRewards;

    // Constants
    uint256 public constant MESSAGE_FEE = 0.00001 ether;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant REFERRAL_BONUS = 0.0001 ether;
    uint256 public constant MAX_REFERRAL_DEPTH = 5;

    constructor() {
        _messageIdCounter.increment();
        _initializeReferralTiers();
        _initializeMilestones();
    }

    /**
     * @dev Initialize referral tier structure
     */
    function _initializeReferralTiers() private {
        // Tier 1: 50% of message fees from direct referrals
        referralTiers.push(ReferralTier({
            tier: 1,
            percentage: 50,
            maxDepth: 1
        }));

        // Tier 2: 25% from 2nd level
        referralTiers.push(ReferralTier({
            tier: 2,
            percentage: 25,
            maxDepth: 2
        }));

        // Tier 3: 15% from 3rd level
        referralTiers.push(ReferralTier({
            tier: 3,
            percentage: 15,
            maxDepth: 3
        }));

        // Tier 4: 7% from 4th level
        referralTiers.push(ReferralTier({
            tier: 4,
            percentage: 7,
            maxDepth: 4
        }));

        // Tier 5: 3% from 5th level
        referralTiers.push(ReferralTier({
            tier: 5,
            percentage: 3,
            maxDepth: 5
        }));
    }

    /**
     * @dev Initialize milestone rewards
     */
    function _initializeMilestones() private {
        // 10 referrals
        milestoneTargets.push(10);
        milestoneRewards.push(0.001 ether);

        // 50 referrals
        milestoneTargets.push(50);
        milestoneRewards.push(0.005 ether);

        // 100 referrals
        milestoneTargets.push(100);
        milestoneRewards.push(0.01 ether);

        // 500 referrals
        milestoneTargets.push(500);
        milestoneRewards.push(0.05 ether);

        // 1000 referrals
        milestoneTargets.push(1000);
        milestoneRewards.push(0.1 ether);
    }

    /**
     * @dev Register new user with optional referrer
     */
    function registerUser(address _referrer) 
        external 
        nonReentrant 
    {
        require(!users[msg.sender].isActive, "Already registered");
        require(_referrer != msg.sender, "Cannot refer yourself");

        if (_referrer != address(0)) {
            require(users[_referrer].isActive, "Referrer not registered");
        }

        users[msg.sender] = User({
            wallet: msg.sender,
            referrer: _referrer,
            registeredAt: block.timestamp,
            totalReferred: 0,
            directReferrals: 0,
            totalEarned: 0,
            messagesSent: 0,
            isActive: true
        });

        if (_referrer != address(0)) {
            users[_referrer].directReferrals++;
            userReferrals[_referrer].push(msg.sender);
            
            // Update total referred count up the chain
            _updateReferralChain(_referrer);

            // Pay registration bonus to referrer
            pendingRewards[_referrer] += REFERRAL_BONUS;
        }

        emit UserRegistered(msg.sender, _referrer, block.timestamp);
    }

    /**
     * @dev Update referral counts through the chain
     */
    function _updateReferralChain(address _referrer) private {
        address current = _referrer;
        uint256 depth = 0;

        while (current != address(0) && depth < MAX_REFERRAL_DEPTH) {
            users[current].totalReferred++;
            
            // Check for milestone achievements
            _checkMilestones(current);
            
            current = users[current].referrer;
            depth++;
        }
    }

    /**
     * @dev Check and award milestone achievements
     */
    function _checkMilestones(address _user) private {
        uint256 totalReferred = users[_user].totalReferred;

        for (uint256 i = 0; i < milestoneTargets.length; i++) {
            if (totalReferred == milestoneTargets[i]) {
                uint256 reward = milestoneRewards[i];
                pendingRewards[_user] += reward;
                
                emit MilestoneAchieved(_user, milestoneTargets[i], reward, block.timestamp);
                break;
            }
        }
    }

    /**
     * @dev Send message with referral rewards
     */
    function sendMessage(
        address _recipient,
        string memory _content
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        require(users[msg.sender].isActive, "Sender not registered");
        require(_recipient != address(0), "Invalid recipient");
        require(_recipient != msg.sender, "Cannot message yourself");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        require(msg.value >= MESSAGE_FEE, "Insufficient fee");

        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        messages[messageId] = Message({
            id: messageId,
            sender: msg.sender,
            recipient: _recipient,
            content: _content,
            timestamp: block.timestamp,
            fee: msg.value
        });

        userMessages[msg.sender].push(messageId);
        users[msg.sender].messagesSent++;

        // Distribute referral rewards up the chain
        _distributeReferralRewards(msg.sender, msg.value);

        emit MessageSent(messageId, msg.sender, _recipient, block.timestamp);

        return messageId;
    }

    /**
     * @dev Distribute referral rewards through the chain
     */
    function _distributeReferralRewards(
        address _sender,
        uint256 _fee
    ) 
        private 
    {
        address current = users[_sender].referrer;
        uint256 depth = 0;

        while (current != address(0) && depth < referralTiers.length) {
            ReferralTier memory tier = referralTiers[depth];
            uint256 reward = (_fee * tier.percentage) / 100;

            pendingRewards[current] += reward;
            users[current].totalEarned += reward;

            emit ReferralRewardPaid(
                current,
                _sender,
                reward,
                tier.tier,
                block.timestamp
            );

            current = users[current].referrer;
            depth++;
        }
    }

    /**
     * @dev Claim pending referral rewards
     */
    function claimRewards() 
        external 
        nonReentrant 
    {
        uint256 amount = pendingRewards[msg.sender];
        require(amount > 0, "No pending rewards");

        pendingRewards[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
    }

    /**
     * @dev Get user's referral stats
     */
    function getUserStats(address _user) 
        external 
        view 
        returns (
            address referrer,
            uint256 directReferrals,
            uint256 totalReferred,
            uint256 totalEarned,
            uint256 pendingReward,
            uint256 messagesSent,
            uint256 registeredAt
        )
    {
        User memory user = users[_user];
        return (
            user.referrer,
            user.directReferrals,
            user.totalReferred,
            user.totalEarned,
            pendingRewards[_user],
            user.messagesSent,
            user.registeredAt
        );
    }

    /**
     * @dev Get user's direct referrals
     */
    function getUserReferrals(address _user) 
        external 
        view 
        returns (address[] memory) 
    {
        return userReferrals[_user];
    }

    /**
     * @dev Get referral chain depth
     */
    function getReferralChainDepth(address _user) 
        external 
        view 
        returns (uint256) 
    {
        address current = users[_user].referrer;
        uint256 depth = 0;

        while (current != address(0) && depth < MAX_REFERRAL_DEPTH) {
            current = users[current].referrer;
            depth++;
        }

        return depth;
    }

    /**
     * @dev Get message details
     */
    function getMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address recipient,
            string memory content,
            uint256 timestamp,
            uint256 fee
        )
    {
        Message memory message = messages[_messageId];
        return (
            message.id,
            message.sender,
            message.recipient,
            message.content,
            message.timestamp,
            message.fee
        );
    }

    /**
     * @dev Withdraw contract balance (only owner)
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdraw failed");
    }
}
