// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SavingsMessaging
 * @dev Messages with automatic micro-savings deposits
 * @author Swift v2 Team
 */
contract SavingsMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event MessageWithSavingsSent(
        uint256 indexed messageId,
        address indexed sender,
        address[] recipients,
        uint256 savingsAmount,
        uint256 timestamp
    );

    event SavingsWithdrawn(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );

    event SavingsGoalSet(
        address indexed user,
        uint256 goalAmount,
        string goalName,
        uint256 timestamp
    );

    // Structs
    struct SavingsMessage {
        uint256 id;
        address sender;
        address[] recipients;
        string content;
        uint256 savingsDeposit; // Auto-saved amount per message
        uint256 timestamp;
    }

    struct SavingsGoal {
        string name;
        uint256 targetAmount;
        uint256 currentAmount;
        uint256 createdAt;
        bool isCompleted;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => SavingsMessage) public savingsMessages;
    mapping(address => uint256) public userSavingsBalance;
    mapping(address => SavingsGoal) public userSavingsGoals;
    mapping(address => uint256[]) public userMessages;

    // Celo cUSD address
    address public constant CUSD_ADDRESS = 0x765DE816845861e75A25fCA122bb6898B8B1282a;

    // Constants
    uint256 public constant MAX_RECIPIENTS = 500;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant DEFAULT_SAVINGS = 100000000000000; // 0.0001 cUSD per message
    uint256 public constant MIN_SAVINGS = 10000000000000; // 0.00001 cUSD
    uint256 public constant MAX_SAVINGS = 10000000000000000; // 0.01 cUSD

    constructor() {
        _messageIdCounter.increment();
    }

    /**
     * @dev Set savings goal
     * @param _goalName Name of the goal
     * @param _targetAmount Target amount to save
     */
    function setSavingsGoal(string memory _goalName, uint256 _targetAmount) 
        external 
    {
        require(bytes(_goalName).length > 0, "Goal name cannot be empty");
        require(_targetAmount > 0, "Target must be greater than 0");
        
        SavingsGoal storage goal = userSavingsGoals[msg.sender];
        goal.name = _goalName;
        goal.targetAmount = _targetAmount;
        goal.createdAt = block.timestamp;
        goal.isCompleted = false;
        goal.currentAmount = userSavingsBalance[msg.sender];

        emit SavingsGoalSet(msg.sender, _targetAmount, _goalName, block.timestamp);
    }

    /**
     * @dev Send message with automatic savings
     * @param _recipients Array of recipients
     * @param _content Message content
     * @param _savingsAmount Amount to auto-save with this message
     */
    function sendMessageWithSavings(
        address[] memory _recipients,
        string memory _content,
        uint256 _savingsAmount
    ) 
        external 
        nonReentrant 
    {
        require(_recipients.length > 0, "No recipients");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        require(_savingsAmount >= MIN_SAVINGS, "Savings amount too small");
        require(_savingsAmount <= MAX_SAVINGS, "Savings amount too large");
        
        IERC20 cusd = IERC20(CUSD_ADDRESS);
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        SavingsMessage storage message = savingsMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.content = _content;
        message.savingsDeposit = _savingsAmount;
        message.timestamp = block.timestamp;

        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] != address(0) && _recipients[i] != msg.sender) {
                message.recipients.push(_recipients[i]);
            }
        }

        require(message.recipients.length > 0, "No valid recipients");

        // Transfer savings amount to contract
        require(
            cusd.transferFrom(msg.sender, address(this), _savingsAmount),
            "Savings transfer failed"
        );

        // Update user's savings balance
        userSavingsBalance[msg.sender] += _savingsAmount;

        // Check if goal reached
        SavingsGoal storage goal = userSavingsGoals[msg.sender];
        if (!goal.isCompleted && userSavingsBalance[msg.sender] >= goal.targetAmount) {
            goal.isCompleted = true;
            goal.currentAmount = userSavingsBalance[msg.sender];
        }

        userMessages[msg.sender].push(messageId);

        emit MessageWithSavingsSent(
            messageId,
            msg.sender,
            message.recipients,
            _savingsAmount,
            block.timestamp
        );
    }

    /**
     * @dev Withdraw savings
     * @param _amount Amount to withdraw
     */
    function withdrawSavings(uint256 _amount) 
        external 
        nonReentrant 
    {
        require(userSavingsBalance[msg.sender] >= _amount, "Insufficient savings");
        require(_amount > 0, "Amount must be greater than 0");

        userSavingsBalance[msg.sender] -= _amount;

        // Update goal progress
        SavingsGoal storage goal = userSavingsGoals[msg.sender];
        if (goal.currentAmount > 0) {
            goal.currentAmount = userSavingsBalance[msg.sender];
            if (userSavingsBalance[msg.sender] < goal.targetAmount) {
                goal.isCompleted = false;
            }
        }

        IERC20 cusd = IERC20(CUSD_ADDRESS);
        require(
            cusd.transfer(msg.sender, _amount),
            "Withdrawal failed"
        );

        emit SavingsWithdrawn(msg.sender, _amount, block.timestamp);
    }

    /**
     * @dev Deposit additional savings
     * @param _amount Amount to deposit
     */
    function depositSavings(uint256 _amount) 
        external 
        nonReentrant 
    {
        require(_amount > 0, "Amount must be greater than 0");
        
        IERC20 cusd = IERC20(CUSD_ADDRESS);

        require(
            cusd.transferFrom(msg.sender, address(this), _amount),
            "Deposit failed"
        );

        userSavingsBalance[msg.sender] += _amount;

        // Check if goal reached
        SavingsGoal storage goal = userSavingsGoals[msg.sender];
        if (!goal.isCompleted && userSavingsBalance[msg.sender] >= goal.targetAmount) {
            goal.isCompleted = true;
            goal.currentAmount = userSavingsBalance[msg.sender];
        }
    }

    /**
     * @dev Get savings message details
     */
    function getSavingsMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address[] memory recipients,
            string memory content,
            uint256 savingsDeposit,
            uint256 timestamp
        )
    {
        SavingsMessage storage message = savingsMessages[_messageId];
        return (
            message.id,
            message.sender,
            message.recipients,
            message.content,
            message.savingsDeposit,
            message.timestamp
        );
    }

    /**
     * @dev Get user's savings balance
     */
    function getUserSavingsBalance(address _user) external view returns (uint256) {
        return userSavingsBalance[_user];
    }

    /**
     * @dev Get user's savings goal
     */
    function getUserSavingsGoal(address _user) 
        external 
        view 
        returns (
            string memory name,
            uint256 targetAmount,
            uint256 currentAmount,
            uint256 createdAt,
            bool isCompleted
        )
    {
        SavingsGoal storage goal = userSavingsGoals[_user];
        return (
            goal.name,
            goal.targetAmount,
            userSavingsBalance[_user], // Always get current balance
            goal.createdAt,
            goal.isCompleted
        );
    }

    /**
     * @dev Get user's messages
     */
    function getUserMessages(address _user) external view returns (uint256[] memory) {
        return userMessages[_user];
    }

    /**
     * @dev Emergency withdraw (only owner)
     */
    function emergencyWithdraw() external onlyOwner nonReentrant {
        IERC20 cusd = IERC20(CUSD_ADDRESS);
        uint256 balance = cusd.balanceOf(address(this));
        require(balance > 0, "No balance");

        require(cusd.transfer(owner(), balance), "Withdraw failed");
    }
}
