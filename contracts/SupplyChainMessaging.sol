// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title SupplyChainMessaging
 * @dev Messaging-based supply chain tracking
 * @author Swift v2 Team
 */
contract SupplyChainMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event ItemCreated(
        uint256 indexed itemId,
        address indexed creator,
        string description,
        uint256 timestamp
    );

    event StatusUpdated(
        uint256 indexed itemId,
        address indexed handler,
        string status,
        string location,
        uint256 timestamp
    );

    event CustodyTransferred(
        uint256 indexed itemId,
        address indexed from,
        address indexed to,
        uint256 timestamp
    );

    // Structs
    struct StatusUpdate {
        address handler;
        string status;
        string location;
        uint256 timestamp;
        string notes;
    }

    struct Item {
        uint256 id;
        address creator;
        address currentHandler;
        string description;
        bool isActive;
        uint256 createdAt;
    }

    // State variables
    Counters.Counter private _itemIdCounter;
    mapping(uint256 => Item) public items;
    mapping(uint256 => StatusUpdate[]) public itemHistory;
    mapping(address => uint256[]) public userItems; // Items currently handled by user

    constructor() {
        _itemIdCounter.increment();
    }

    /**
     * @dev Create a new supply chain item
     * @param _description Description of the item
     * @param _initialLocation Initial location
     */
    function createItem(
        string memory _description,
        string memory _initialLocation
    ) external nonReentrant {
        require(bytes(_description).length > 0, "Description required");

        uint256 itemId = _itemIdCounter.current();
        _itemIdCounter.increment();

        Item storage item = items[itemId];
        item.id = itemId;
        item.creator = msg.sender;
        item.currentHandler = msg.sender;
        item.description = _description;
        item.isActive = true;
        item.createdAt = block.timestamp;

        // Record initial status
        StatusUpdate memory update = StatusUpdate({
            handler: msg.sender,
            status: "CREATED",
            location: _initialLocation,
            timestamp: block.timestamp,
            notes: "Item created"
        });
        itemHistory[itemId].push(update);

        userItems[msg.sender].push(itemId);

        emit ItemCreated(itemId, msg.sender, _description, block.timestamp);
        emit StatusUpdated(itemId, msg.sender, "CREATED", _initialLocation, block.timestamp);
    }

    /**
     * @dev Update status of an item
     * @param _itemId Item ID
     * @param _status New status
     * @param _location Current location
     * @param _notes Additional notes
     */
    function updateStatus(
        uint256 _itemId,
        string memory _status,
        string memory _location,
        string memory _notes
    ) external nonReentrant {
        Item storage item = items[_itemId];
        require(item.isActive, "Item not active");
        require(item.currentHandler == msg.sender, "Not current handler");

        StatusUpdate memory update = StatusUpdate({
            handler: msg.sender,
            status: _status,
            location: _location,
            timestamp: block.timestamp,
            notes: _notes
        });
        itemHistory[_itemId].push(update);

        emit StatusUpdated(_itemId, msg.sender, _status, _location, block.timestamp);
    }

    /**
     * @dev Transfer custody of an item
     * @param _itemId Item ID
     * @param _to New handler address
     * @param _location Location of transfer
     * @param _notes Transfer notes
     */
    function transferCustody(
        uint256 _itemId,
        address _to,
        string memory _location,
        string memory _notes
    ) external nonReentrant {
        require(_to != address(0), "Invalid recipient");
        Item storage item = items[_itemId];
        require(item.isActive, "Item not active");
        require(item.currentHandler == msg.sender, "Not current handler");

        // Record transfer status
        StatusUpdate memory update = StatusUpdate({
            handler: msg.sender,
            status: "TRANSFERRED",
            location: _location,
            timestamp: block.timestamp,
            notes: _notes
        });
        itemHistory[_itemId].push(update);

        address previousHandler = item.currentHandler;
        item.currentHandler = _to;

        // Update user mappings (simplified, not removing from previous for gas efficiency in this demo)
        userItems[_to].push(_itemId);

        emit CustodyTransferred(_itemId, previousHandler, _to, block.timestamp);
    }

    /**
     * @dev Mark item as completed/delivered
     */
    function completeItem(uint256 _itemId, string memory _location) external nonReentrant {
        Item storage item = items[_itemId];
        require(item.isActive, "Item not active");
        require(item.currentHandler == msg.sender, "Not current handler");

        item.isActive = false;

        StatusUpdate memory update = StatusUpdate({
            handler: msg.sender,
            status: "COMPLETED",
            location: _location,
            timestamp: block.timestamp,
            notes: "Item delivery completed"
        });
        itemHistory[_itemId].push(update);

        emit StatusUpdated(_itemId, msg.sender, "COMPLETED", _location, block.timestamp);
    }

    /**
     * @dev Get item history
     */
    function getItemHistory(uint256 _itemId) external view returns (StatusUpdate[] memory) {
        return itemHistory[_itemId];
    }

    /**
     * @dev Get item details
     */
    function getItem(uint256 _itemId) external view returns (
        address creator,
        address currentHandler,
        string memory description,
        bool isActive,
        uint256 createdAt
    ) {
        Item storage item = items[_itemId];
        return (
            item.creator,
            item.currentHandler,
            item.description,
            item.isActive,
            item.createdAt
        );
    }
}
