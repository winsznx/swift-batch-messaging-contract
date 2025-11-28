// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title CarbonOffsetMessaging
 * @dev Carbon-neutral messaging with automatic carbon offset purchases
 * @author Swift v2 Team
 */
contract CarbonOffsetMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event CarbonNeutralMessageSent(
        uint256 indexed messageId,
        address indexed sender,
        address[] recipients,
        uint256 carbonOffsetAmount,
        uint256 timestamp
    );

    event CarbonOffsetPurchased(
        uint256 indexed messageId,
        address indexed offsetProvider,
        uint256 amount,
        uint256 timestamp
    );

    // Structs
    struct CarbonMessage {
        uint256 id;
        address sender;
        address[] recipients;
        string content;
        uint256 carbonOffsetAmount; // in cUSD
        uint256 timestamp;
        address offsetProvider;
        bool isVerified;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => CarbonMessage) public carbonMessages;
    mapping(address => uint256[]) public userMessages;
    mapping(address => bool) public approvedOffsetProviders;
    mapping(address => uint256) public totalCarbonOffset; // User's total offset contribution

    // Celo cUSD address
    address public constant CUSD_ADDRESS = 0x765DE816845861e75A25fCA122bb6898B8B1282a;

    // Constants
    uint256 public constant MAX_RECIPIENTS = 500;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant CARBON_OFFSET_PER_MESSAGE = 1000000000000000; // 0.001 cUSD per message
    uint256 public constant MESSAGE_FEE = 100000000000000; // 0.0001 cUSD

    // Default carbon offset provider
    address public defaultOffsetProvider;

    constructor(address _defaultOffsetProvider) {
        _messageIdCounter.increment();
        defaultOffsetProvider = _defaultOffsetProvider;
        approvedOffsetProviders[_defaultOffsetProvider] = true;
    }

    /**
     * @dev Add approved carbon offset provider
     */
    function addOffsetProvider(address _provider) external onlyOwner {
        require(_provider != address(0), "Invalid provider");
        approvedOffsetProviders[_provider] = true;
    }

    /**
     * @dev Remove offset provider
     */
    function removeOffsetProvider(address _provider) external onlyOwner {
        approvedOffsetProviders[_provider] = false;
    }

    /**
     * @dev Send carbon-neutral message
     * @param _recipients Array of recipient addresses
     * @param _content Message content
     * @param _offsetProvider Carbon offset provider address
     */
    function sendCarbonNeutralMessage(
        address[] memory _recipients,
        string memory _content,
        address _offsetProvider
    ) 
        external 
        nonReentrant 
    {
        require(_recipients.length > 0, "No recipients");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        
        address provider = _offsetProvider == address(0) ? defaultOffsetProvider : _offsetProvider;
        require(approvedOffsetProviders[provider], "Provider not approved");
        
        IERC20 cusd = IERC20(CUSD_ADDRESS);
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        CarbonMessage storage message = carbonMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.content = _content;
        message.carbonOffsetAmount = CARBON_OFFSET_PER_MESSAGE;
        message.timestamp = block.timestamp;
        message.offsetProvider = provider;
        message.isVerified = false;

        uint256 validCount = 0;
        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] != address(0) && _recipients[i] != msg.sender) {
                message.recipients.push(_recipients[i]);
                validCount++;
            }
        }

        require(validCount > 0, "No valid recipients");

        // Calculate total cost: message fee + carbon offset
        uint256 totalCost = MESSAGE_FEE + CARBON_OFFSET_PER_MESSAGE;
        
        // Transfer from sender
        require(
            cusd.transferFrom(msg.sender, address(this), totalCost),
            "Payment failed"
        );

        // Transfer carbon offset to provider
        require(
            cusd.transfer(provider, CARBON_OFFSET_PER_MESSAGE),
            "Offset transfer failed"
        );

        // Track user's carbon offset contribution
        totalCarbonOffset[msg.sender] += CARBON_OFFSET_PER_MESSAGE;

        userMessages[msg.sender].push(messageId);

        emit CarbonNeutralMessageSent(
            messageId,
            msg.sender,
            message.recipients,
            CARBON_OFFSET_PER_MESSAGE,
            block.timestamp
        );

        emit CarbonOffsetPurchased(
            messageId,
            provider,
            CARBON_OFFSET_PER_MESSAGE,
            block.timestamp
        );
    }

    /**
     * @dev Verify carbon offset (only offset provider)
     * @param _messageId ID of the message
     */
    function verifyCarbonOffset(uint256 _messageId) 
        external 
    {
        CarbonMessage storage message = carbonMessages[_messageId];
        require(message.offsetProvider == msg.sender, "Only provider can verify");
        require(!message.isVerified, "Already verified");

        message.isVerified = true;
    }

    /**
     * @dev Get carbon message details
     */
    function getCarbonMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address[] memory recipients,
            string memory content,
            uint256 carbonOffsetAmount,
            uint256 timestamp,
            address offsetProvider,
            bool isVerified
        )
    {
        CarbonMessage storage message = carbonMessages[_messageId];
        return (
            message.id,
            message.sender,
            message.recipients,
            message.content,
            message.carbonOffsetAmount,
            message.timestamp,
            message.offsetProvider,
            message.isVerified
        );
    }

    /**
     * @dev Get user's total carbon offset contribution
     */
    function getUserCarbonOffset(address _user) external view returns (uint256) {
        return totalCarbonOffset[_user];
    }

    /**
     * @dev Get user's messages
     */
    function getUserMessages(address _user) external view returns (uint256[] memory) {
        return userMessages[_user];
    }

    /**
     * @dev Update default offset provider
     */
    function setDefaultOffsetProvider(address _provider) external onlyOwner {
        require(approvedOffsetProviders[_provider], "Provider not approved");
        defaultOffsetProvider = _provider;
    }

    /**
     * @dev Withdraw collected fees (only owner)
     */
    function withdraw() external onlyOwner nonReentrant {
        IERC20 cusd = IERC20(CUSD_ADDRESS);
        uint256 balance = cusd.balanceOf(address(this));
        require(balance > 0, "No balance");

        require(cusd.transfer(owner(), balance), "Withdraw failed");
    }
}
