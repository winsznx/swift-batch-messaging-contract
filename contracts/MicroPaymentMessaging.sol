// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MicroPaymentMessaging
 * @dev Ultra-low-cost messaging for micropayments using Celo's low fees
 * @author Swift v2 Team
 */
contract MicroPaymentMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event MicroPaymentSent(
        uint256 indexed paymentId,
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        string message,
        uint256 timestamp
    );

    // Structs
    struct MicroPayment {
        uint256 id;
        address sender;
        address recipient;
        uint256 amount; // In cUSD (smallest units)
        string message;
        uint256 timestamp;
        bool isClaimed;
    }

    // State variables
    Counters.Counter private _paymentIdCounter;
    mapping(uint256 => MicroPayment) public microPayments;
    mapping(address => uint256[]) public userSentPayments;
    mapping(address => uint256[]) public userReceivedPayments;

    // Celo cUSD address
    address public constant CUSD_ADDRESS = 0x765DE816845861e75A25fCA122bb6898B8B1282a;

    // Constants - Ultra low amounts for micropayments
    uint256 public constant MIN_MICROPAYMENT = 1000; // 0.000001 cUSD (1 millionth)
    uint256 public constant MAX_MESSAGE_LENGTH = 280; // Tweet-length for efficiency
    uint256 public constant BATCH_DISCOUNT_THRESHOLD = 10;

    constructor() {
        _paymentIdCounter.increment();
    }

    /**
     * @dev Send micropayment with message
     * @param _recipient Recipient address
     * @param _amount Amount in cUSD smallest units
     * @param _message Short message
     */
    function sendMicroPayment(
        address _recipient,
        uint256 _amount,
        string memory _message
    ) 
        external 
        nonReentrant 
    {
        require(_recipient != address(0), "Invalid recipient");
        require(_recipient != msg.sender, "Cannot send to yourself");
        require(_amount >= MIN_MICROPAYMENT, "Amount too small");
        require(bytes(_message).length <= MAX_MESSAGE_LENGTH, "Message too long");
        
        IERC20 cusd = IERC20(CUSD_ADDRESS);
        
        uint256 paymentId = _paymentIdCounter.current();
        _paymentIdCounter.increment();

        MicroPayment storage payment = microPayments[paymentId];
        payment.id = paymentId;
        payment.sender = msg.sender;
        payment.recipient = _recipient;
        payment.amount = _amount;
        payment.message = _message;
        payment.timestamp = block.timestamp;
        payment.isClaimed = false;

        // Transfer cUSD
        require(
            cusd.transferFrom(msg.sender, address(this), _amount),
            "Transfer failed"
        );

        userSentPayments[msg.sender].push(paymentId);
        userReceivedPayments[_recipient].push(paymentId);

        emit MicroPaymentSent(
            paymentId,
            msg.sender,
            _recipient,
            _amount,
            _message,
            block.timestamp
        );
    }

    /**
     * @dev Send batch micropayments (gas optimized)
     * @param _recipients Array of recipients
     * @param _amounts Array of amounts
     * @param _message Shared message for all
     */
    function sendBatchMicroPayments(
        address[] memory _recipients,
        uint256[] memory _amounts,
        string memory _message
    ) 
        external 
        nonReentrant 
    {
        require(_recipients.length == _amounts.length, "Length mismatch");
        require(_recipients.length > 0, "No recipients");
        require(bytes(_message).length <= MAX_MESSAGE_LENGTH, "Message too long");
        
        IERC20 cusd = IERC20(CUSD_ADDRESS);
        uint256 totalAmount = 0;
        
        // Calculate total and validate
        for (uint256 i = 0; i < _amounts.length; i++) {
            require(_amounts[i] >= MIN_MICROPAYMENT, "Amount too small");
            totalAmount += _amounts[i];
        }

        // Single transfer from sender
        require(
            cusd.transferFrom(msg.sender, address(this), totalAmount),
            "Batch transfer failed"
        );

        // Create individual payment records
        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] == address(0) || _recipients[i] == msg.sender) {
                continue;
            }

            uint256 paymentId = _paymentIdCounter.current();
            _paymentIdCounter.increment();

            MicroPayment storage payment = microPayments[paymentId];
            payment.id = paymentId;
            payment.sender = msg.sender;
            payment.recipient = _recipients[i];
            payment.amount = _amounts[i];
            payment.message = _message;
            payment.timestamp = block.timestamp;
            payment.isClaimed = false;

            userSentPayments[msg.sender].push(paymentId);
            userReceivedPayments[_recipients[i]].push(paymentId);

            emit MicroPaymentSent(
                paymentId,
                msg.sender,
                _recipients[i],
                _amounts[i],
                _message,
                block.timestamp
            );
        }
    }

    /**
     * @dev Claim micropayment
     * @param _paymentId ID of the payment
     */
    function claimMicroPayment(uint256 _paymentId) 
        external 
        nonReentrant 
    {
        MicroPayment storage payment = microPayments[_paymentId];
        require(payment.recipient == msg.sender, "Not the recipient");
        require(!payment.isClaimed, "Already claimed");

        payment.isClaimed = true;

        IERC20 cusd = IERC20(CUSD_ADDRESS);
        require(
            cusd.transfer(msg.sender, payment.amount),
            "Claim failed"
        );
    }

    /**
     * @dev Claim multiple micropayments in one transaction
     * @param _paymentIds Array of payment IDs
     */
    function claimBatchMicroPayments(uint256[] memory _paymentIds) 
        external 
        nonReentrant 
    {
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < _paymentIds.length; i++) {
            MicroPayment storage payment = microPayments[_paymentIds[i]];
            
            if (payment.recipient == msg.sender && !payment.isClaimed) {
                payment.isClaimed = true;
                totalAmount += payment.amount;
            }
        }

        require(totalAmount > 0, "Nothing to claim");

        IERC20 cusd = IERC20(CUSD_ADDRESS);
        require(
            cusd.transfer(msg.sender, totalAmount),
            "Batch claim failed"
        );
    }

    /**
     * @dev Get micropayment details
     */
    function getMicroPayment(uint256 _paymentId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address recipient,
            uint256 amount,
            string memory message,
            uint256 timestamp,
            bool isClaimed
        )
    {
        MicroPayment storage payment = microPayments[_paymentId];
        return (
            payment.id,
            payment.sender,
            payment.recipient,
            payment.amount,
            payment.message,
            payment.timestamp,
            payment.isClaimed
        );
    }

    /**
     * @dev Get user's sent payments
     */
    function getUserSentPayments(address _user) external view returns (uint256[] memory) {
        return userSentPayments[_user];
    }

    /**
     * @dev Get user's received payments
     */
    function getUserReceivedPayments(address _user) external view returns (uint256[] memory) {
        return userReceivedPayments[_user];
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
