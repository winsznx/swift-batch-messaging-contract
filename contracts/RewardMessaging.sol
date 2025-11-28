// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title RewardMessaging
 * @dev A contract that rewards recipients with tokens for reading/interacting
 * @author Swift v2 Team
 */
contract RewardMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event RewardMessageSent(
        uint256 indexed messageId,
        address indexed sender,
        address[] recipients,
        uint256 rewardPerRecipient,
        uint256 timestamp
    );

    event RewardClaimed(
        uint256 indexed messageId,
        address indexed recipient,
        uint256 amount,
        uint256 timestamp
    );

    // Structs
    struct RewardMessage {
        uint256 id;
        address sender;
        address[] recipients;
        string content;
        uint256 rewardPerRecipient;
        address rewardToken; // address(0) for ETH
        mapping(address => bool) hasClaimed;
        uint256 claimedCount;
        uint256 timestamp;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => RewardMessage) public rewardMessages;
    mapping(address => uint256[]) public userSentMessages;
    mapping(address => uint256[]) public userReceivedMessages;

    // Constants
    uint256 public constant MESSAGE_FEE = 0.000003 ether;
    uint256 public constant MAX_RECIPIENTS = 500;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;

    constructor() {
        _messageIdCounter.increment();
    }

    /**
     * @dev Send a reward message with ETH
     * @param _recipients Array of recipient addresses
     * @param _content Message content
     * @param _rewardPerRecipient Reward amount per recipient in wei
     */
    function sendRewardMessageETH(
        address[] memory _recipients,
        string memory _content,
        uint256 _rewardPerRecipient
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(_recipients.length > 0, "No recipients");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        require(_rewardPerRecipient > 0, "Reward must be greater than 0");
        
        uint256 totalReward = _rewardPerRecipient * _recipients.length;
        require(msg.value >= MESSAGE_FEE + totalReward, "Insufficient payment");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        RewardMessage storage message = rewardMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.content = _content;
        message.rewardPerRecipient = _rewardPerRecipient;
        message.rewardToken = address(0); // ETH
        message.timestamp = block.timestamp;
        message.claimedCount = 0;

        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] != address(0) && _recipients[i] != msg.sender) {
                message.recipients.push(_recipients[i]);
                userReceivedMessages[_recipients[i]].push(messageId);
            }
        }

        require(message.recipients.length > 0, "No valid recipients");

        userSentMessages[msg.sender].push(messageId);

        emit RewardMessageSent(
            messageId,
            msg.sender,
            message.recipients,
            _rewardPerRecipient,
            block.timestamp
        );
    }

    /**
     * @dev Send a reward message with ERC20 tokens
     * @param _recipients Array of recipient addresses
     * @param _content Message content
     * @param _rewardToken ERC20 token address
     * @param _rewardPerRecipient Reward amount per recipient
     */
    function sendRewardMessageToken(
        address[] memory _recipients,
        string memory _content,
        address _rewardToken,
        uint256 _rewardPerRecipient
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= MESSAGE_FEE, "Insufficient fee");
        require(_recipients.length > 0, "No recipients");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        require(_rewardToken != address(0), "Invalid token address");
        require(_rewardPerRecipient > 0, "Reward must be greater than 0");
        
        uint256 totalReward = _rewardPerRecipient * _recipients.length;
        
        // Transfer tokens to contract
        IERC20 token = IERC20(_rewardToken);
        require(
            token.transferFrom(msg.sender, address(this), totalReward),
            "Token transfer failed"
        );
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        RewardMessage storage message = rewardMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.content = _content;
        message.rewardPerRecipient = _rewardPerRecipient;
        message.rewardToken = _rewardToken;
        message.timestamp = block.timestamp;
        message.claimedCount = 0;

        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] != address(0) && _recipients[i] != msg.sender) {
                message.recipients.push(_recipients[i]);
                userReceivedMessages[_recipients[i]].push(messageId);
            }
        }

        require(message.recipients.length > 0, "No valid recipients");

        userSentMessages[msg.sender].push(messageId);

        emit RewardMessageSent(
            messageId,
            msg.sender,
            message.recipients,
            _rewardPerRecipient,
            block.timestamp
        );
    }

    /**
     * @dev Claim reward for a message
     * @param _messageId ID of the message
     */
    function claimReward(uint256 _messageId) 
        external 
        nonReentrant 
    {
        RewardMessage storage message = rewardMessages[_messageId];
        require(!message.hasClaimed[msg.sender], "Already claimed");
        
        bool isRecipient = false;
        for (uint256 i = 0; i < message.recipients.length; i++) {
            if (message.recipients[i] == msg.sender) {
                isRecipient = true;
                break;
            }
        }
        require(isRecipient, "Not a recipient");

        message.hasClaimed[msg.sender] = true;
        message.claimedCount++;

        if (message.rewardToken == address(0)) {
            // ETH reward
            (bool success, ) = payable(msg.sender).call{value: message.rewardPerRecipient}("");
            require(success, "ETH transfer failed");
        } else {
            // Token reward
            IERC20 token = IERC20(message.rewardToken);
            require(
                token.transfer(msg.sender, message.rewardPerRecipient),
                "Token transfer failed"
            );
        }

        emit RewardClaimed(_messageId, msg.sender, message.rewardPerRecipient, block.timestamp);
    }

    /**
     * @dev Get reward message details
     */
    function getRewardMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address[] memory recipients,
            string memory content,
            uint256 rewardPerRecipient,
            address rewardToken,
            uint256 claimedCount,
            uint256 timestamp
        )
    {
        RewardMessage storage message = rewardMessages[_messageId];
        return (
            message.id,
            message.sender,
            message.recipients,
            message.content,
            message.rewardPerRecipient,
            message.rewardToken,
            message.claimedCount,
            message.timestamp
        );
    }

    /**
     * @dev Check if recipient has claimed
     */
    function hasClaimed(uint256 _messageId, address _recipient) 
        external 
        view 
        returns (bool)
    {
        return rewardMessages[_messageId].hasClaimed[_recipient];
    }

    /**
     * @dev Get user's sent messages
     */
    function getUserSentMessages(address _user) external view returns (uint256[] memory) {
        return userSentMessages[_user];
    }

    /**
     * @dev Get user's received messages
     */
    function getUserReceivedMessages(address _user) external view returns (uint256[] memory) {
        return userReceivedMessages[_user];
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
