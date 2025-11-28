// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title MultisigMessaging
 * @dev A contract requiring multiple signatures to approve messages
 * @author Swift v2 Team
 */
contract MultisigMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event MessageProposed(
        uint256 indexed messageId,
        address indexed proposer,
        address[] recipients,
        uint256 timestamp
    );

    event MessageApproved(
        uint256 indexed messageId,
        address indexed approver,
        uint256 timestamp
    );

    event MessageExecuted(
        uint256 indexed messageId,
        uint256 timestamp
    );

    // Structs
    struct MultisigMessage {
        uint256 id;
        address proposer;
        address[] recipients;
        string content;
        address[] approvers;
        mapping(address => bool) hasApproved;
        uint256 approvalsCount;
        uint256 requiredApprovals;
        uint256 timestamp;
        bool isExecuted;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => MultisigMessage) public multisigMessages;
    mapping(address => uint256[]) public userProposedMessages;

    // Constants
    uint256 public constant MULTISIG_FEE = 0.000008 ether;
    uint256 public constant MAX_RECIPIENTS = 500;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;

    constructor() {
        _messageIdCounter.increment();
    }

    /**
     * @dev Propose a multisig message
     * @param _recipients Array of recipient addresses
     * @param _content Message content
     * @param _approvers Addresses who can approve
     * @param _requiredApprovals Number of approvals needed
     */
    function proposeMessage(
        address[] memory _recipients,
        string memory _content,
        address[] memory _approvers,
        uint256 _requiredApprovals
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= MULTISIG_FEE, "Insufficient fee");
        require(_recipients.length > 0, "No recipients");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        require(_approvers.length > 0, "No approvers");
        require(_requiredApprovals > 0 && _requiredApprovals <= _approvers.length, "Invalid required approvals");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        MultisigMessage storage message = multisigMessages[messageId];
        message.id = messageId;
        message.proposer = msg.sender;
        message.content = _content;
        message.requiredApprovals = _requiredApprovals;
        message.timestamp = block.timestamp;
        message.isExecuted = false;
        message.approvalsCount = 0;

        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] != address(0)) {
                message.recipients.push(_recipients[i]);
            }
        }

        for (uint256 i = 0; i < _approvers.length; i++) {
            if (_approvers[i] != address(0)) {
                message.approvers.push(_approvers[i]);
            }
        }

        userProposedMessages[msg.sender].push(messageId);

        emit MessageProposed(messageId, msg.sender, message.recipients, block.timestamp);
    }

    /**
     * @dev Approve a multisig message
     * @param _messageId ID of the message
     */
    function approveMessage(uint256 _messageId) 
        external 
        nonReentrant 
    {
        MultisigMessage storage message = multisigMessages[_messageId];
        require(!message.isExecuted, "Already executed");
        require(!message.hasApproved[msg.sender], "Already approved");
        
        bool isApprover = false;
        for (uint256 i = 0; i < message.approvers.length; i++) {
            if (message.approvers[i] == msg.sender) {
                isApprover = true;
                break;
            }
        }
        require(isApprover, "Not an approver");

        message.hasApproved[msg.sender] = true;
        message.approvalsCount++;

        emit MessageApproved(_messageId, msg.sender, block.timestamp);

        // Auto-execute if threshold reached
        if (message.approvalsCount >= message.requiredApprovals) {
            message.isExecuted = true;
            emit MessageExecuted(_messageId, block.timestamp);
        }
    }

    /**
     * @dev Get multisig message details
     */
    function getMultisigMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address proposer,
            address[] memory recipients,
            string memory content,
            address[] memory approvers,
            uint256 approvalsCount,
            uint256 requiredApprovals,
            uint256 timestamp,
            bool isExecuted
        )
    {
        MultisigMessage storage message = multisigMessages[_messageId];
        return (
            message.id,
            message.proposer,
            message.recipients,
            message.content,
            message.approvers,
            message.approvalsCount,
            message.requiredApprovals,
            message.timestamp,
            message.isExecuted
        );
    }

    /**
     * @dev Check if address has approved
     */
    function hasApproved(uint256 _messageId, address _approver) 
        external 
        view 
        returns (bool)
    {
        return multisigMessages[_messageId].hasApproved[_approver];
    }

    /**
     * @dev Get user's proposed messages
     */
    function getUserProposedMessages(address _user) external view returns (uint256[] memory) {
        return userProposedMessages[_user];
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
