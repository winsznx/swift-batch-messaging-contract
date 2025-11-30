// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title EventMessaging
 * @dev Event management with RSVP, ticketing, and attendee messaging
 * @author Swift v2 Team
 */
contract EventMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event EventCreated(
        uint256 indexed eventId,
        address indexed organizer,
        string name,
        uint256 timestamp
    );

    event TicketPurchased(
        uint256 indexed ticketId,
        uint256 indexed eventId,
        address indexed attendee,
        uint256 timestamp
    );

    event RSVPSubmitted(
        uint256 indexed eventId,
        address indexed attendee,
        bool attending,
        uint256 timestamp
    );

    event EventMessageSent(
        uint256 indexed messageId,
        uint256 indexed eventId,
        address indexed sender,
        uint256 timestamp
    );

    event EventCancelled(
        uint256 indexed eventId,
        uint256 timestamp
    );

    // Enums
    enum EventStatus { Upcoming, Ongoing, Completed, Cancelled }
    enum TicketType { Free, Paid, VIP }

    // Structs
    struct Event {
        uint256 id;
        address organizer;
        string name;
        string description;
        string location;
        uint256 startTime;
        uint256 endTime;
        uint256 maxAttendees;
        uint256 ticketPrice;
        uint256 vipTicketPrice;
        uint256 attendeeCount;
        uint256 ticketsSold;
        EventStatus status;
        bool requiresTicket;
        uint256 createdAt;
    }

    struct Ticket {
        uint256 id;
        uint256 eventId;
        address attendee;
        TicketType ticketType;
        uint256 purchasedAt;
        bool isCheckedIn;
        bool isRefunded;
    }

    struct RSVP {
        address attendee;
        bool attending;
        uint256 timestamp;
        string message;
    }

    struct EventMessage {
        uint256 id;
        uint256 eventId;
        address sender;
        string content;
        uint256 timestamp;
        bool isAnnouncement;
    }

    // State variables
    Counters.Counter private _eventIdCounter;
    Counters.Counter private _ticketIdCounter;
    Counters.Counter private _messageIdCounter;
    
    mapping(uint256 => Event) public events;
    mapping(uint256 => Ticket) public tickets;
    mapping(uint256 => EventMessage) public eventMessages;
    mapping(uint256 => mapping(address => RSVP)) public eventRSVPs;
    mapping(uint256 => mapping(address => bool)) public hasTicket;
    mapping(uint256 => uint256[]) public eventTickets;
    mapping(uint256 => uint256[]) public eventMessageList;
    mapping(address => uint256[]) public userEvents;
    mapping(address => uint256[]) public userTickets;

    // Constants
    uint256 public constant MAX_NAME_LENGTH = 200;
    uint256 public constant MAX_DESCRIPTION_LENGTH = 1000;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant MIN_TICKET_PRICE = 0.001 ether;
    uint256 public constant EVENT_CREATION_FEE = 0.0001 ether;
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 3;

    constructor() {
        _eventIdCounter.increment();
        _ticketIdCounter.increment();
        _messageIdCounter.increment();
    }

    /**
     * @dev Create new event
     */
    function createEvent(
        string memory _name,
        string memory _description,
        string memory _location,
        uint256 _startTime,
        uint256 _duration,
        uint256 _maxAttendees,
        bool _requiresTicket,
        uint256 _ticketPrice,
        uint256 _vipTicketPrice
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        require(msg.value >= EVENT_CREATION_FEE, "Insufficient fee");
        require(bytes(_name).length > 0 && bytes(_name).length <= MAX_NAME_LENGTH, "Invalid name");
        require(bytes(_description).length <= MAX_DESCRIPTION_LENGTH, "Description too long");
        require(_startTime > block.timestamp, "Invalid start time");
        require(_duration > 0 && _duration <= 7 days, "Invalid duration");
        require(_maxAttendees > 0, "Invalid max attendees");

        if (_requiresTicket) {
            require(_ticketPrice >= MIN_TICKET_PRICE, "Ticket price too low");
            require(_vipTicketPrice >= _ticketPrice, "VIP price must be higher");
        }

        uint256 eventId = _eventIdCounter.current();
        _eventIdCounter.increment();

        events[eventId] = Event({
            id: eventId,
            organizer: msg.sender,
            name: _name,
            description: _description,
            location: _location,
            startTime: _startTime,
            endTime: _startTime + _duration,
            maxAttendees: _maxAttendees,
            ticketPrice: _ticketPrice,
            vipTicketPrice: _vipTicketPrice,
            attendeeCount: 0,
            ticketsSold: 0,
            status: EventStatus.Upcoming,
            requiresTicket: _requiresTicket,
            createdAt: block.timestamp
        });

        userEvents[msg.sender].push(eventId);

        emit EventCreated(eventId, msg.sender, _name, block.timestamp);

        return eventId;
    }

    /**
     * @dev Purchase ticket for event
     */
    function purchaseTicket(
        uint256 _eventId,
        TicketType _ticketType
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        Event storage event_ = events[_eventId];
        require(event_.status == EventStatus.Upcoming, "Event not available");
        require(event_.requiresTicket, "Event doesn't require tickets");
        require(!hasTicket[_eventId][msg.sender], "Already has ticket");
        require(event_.ticketsSold < event_.maxAttendees, "Event sold out");
        require(block.timestamp < event_.startTime, "Event already started");

        uint256 ticketPrice;
        if (_ticketType == TicketType.VIP) {
            ticketPrice = event_.vipTicketPrice;
        } else if (_ticketType == TicketType.Paid) {
            ticketPrice = event_.ticketPrice;
        } else {
            revert("Invalid ticket type");
        }

        require(msg.value >= ticketPrice, "Insufficient payment");

        uint256 ticketId = _ticketIdCounter.current();
        _ticketIdCounter.increment();

        tickets[ticketId] = Ticket({
            id: ticketId,
            eventId: _eventId,
            attendee: msg.sender,
            ticketType: _ticketType,
            purchasedAt: block.timestamp,
            isCheckedIn: false,
            isRefunded: false
        });

        hasTicket[_eventId][msg.sender] = true;
        event_.ticketsSold++;
        event_.attendeeCount++;
        eventTickets[_eventId].push(ticketId);
        userTickets[msg.sender].push(ticketId);

        emit TicketPurchased(ticketId, _eventId, msg.sender, block.timestamp);

        return ticketId;
    }

    /**
     * @dev Submit RSVP for free event
     */
    function submitRSVP(
        uint256 _eventId,
        bool _attending,
        string memory _message
    ) 
        external 
        nonReentrant 
    {
        Event storage event_ = events[_eventId];
        require(event_.status == EventStatus.Upcoming, "Event not available");
        require(!event_.requiresTicket, "Ticketed event requires purchase");
        require(eventRSVPs[_eventId][msg.sender].timestamp == 0, "Already RSVP'd");

        if (_attending) {
            require(event_.attendeeCount < event_.maxAttendees, "Event full");
            event_.attendeeCount++;
        }

        eventRSVPs[_eventId][msg.sender] = RSVP({
            attendee: msg.sender,
            attending: _attending,
            timestamp: block.timestamp,
            message: _message
        });

        emit RSVPSubmitted(_eventId, msg.sender, _attending, block.timestamp);
    }

    /**
     * @dev Send message to event
     */
    function sendEventMessage(
        uint256 _eventId,
        string memory _content,
        bool _isAnnouncement
    ) 
        external 
        nonReentrant 
        returns (uint256)
    {
        Event storage event_ = events[_eventId];
        require(event_.status != EventStatus.Cancelled, "Event cancelled");
        
        if (_isAnnouncement) {
            require(event_.organizer == msg.sender, "Only organizer can announce");
        } else {
            require(
                hasTicket[_eventId][msg.sender] || 
                eventRSVPs[_eventId][msg.sender].attending ||
                event_.organizer == msg.sender,
                "Not attending event"
            );
        }

        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");

        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        eventMessages[messageId] = EventMessage({
            id: messageId,
            eventId: _eventId,
            sender: msg.sender,
            content: _content,
            timestamp: block.timestamp,
            isAnnouncement: _isAnnouncement
        });

        eventMessageList[_eventId].push(messageId);

        emit EventMessageSent(messageId, _eventId, msg.sender, block.timestamp);

        return messageId;
    }

    /**
     * @dev Check in attendee
     */
    function checkInAttendee(uint256 _ticketId) 
        external 
        nonReentrant 
    {
        Ticket storage ticket = tickets[_ticketId];
        Event storage event_ = events[ticket.eventId];
        
        require(event_.organizer == msg.sender, "Only organizer can check in");
        require(!ticket.isCheckedIn, "Already checked in");
        require(!ticket.isRefunded, "Ticket refunded");

        ticket.isCheckedIn = true;

        // Transfer ticket payment to organizer
        uint256 platformFee = (event_.ticketPrice * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 organizerPayment;
        
        if (ticket.ticketType == TicketType.VIP) {
            organizerPayment = event_.vipTicketPrice - platformFee;
        } else {
            organizerPayment = event_.ticketPrice - platformFee;
        }

        (bool success, ) = payable(event_.organizer).call{value: organizerPayment}("");
        require(success, "Payment failed");
    }

    /**
     * @dev Cancel event and refund tickets
     */
    function cancelEvent(uint256 _eventId) 
        external 
        nonReentrant 
    {
        Event storage event_ = events[_eventId];
        require(event_.organizer == msg.sender, "Only organizer can cancel");
        require(event_.status == EventStatus.Upcoming, "Cannot cancel");

        event_.status = EventStatus.Cancelled;

        emit EventCancelled(_eventId, block.timestamp);
    }

    /**
     * @dev Refund ticket
     */
    function refundTicket(uint256 _ticketId) 
        external 
        nonReentrant 
    {
        Ticket storage ticket = tickets[_ticketId];
        Event storage event_ = events[ticket.eventId];
        
        require(
            event_.status == EventStatus.Cancelled ||
            (event_.organizer == msg.sender && block.timestamp < event_.startTime),
            "Cannot refund"
        );
        require(ticket.attendee == msg.sender || event_.organizer == msg.sender, "Not authorized");
        require(!ticket.isRefunded, "Already refunded");

        ticket.isRefunded = true;
        event_.ticketsSold--;

        uint256 refundAmount;
        if (ticket.ticketType == TicketType.VIP) {
            refundAmount = event_.vipTicketPrice;
        } else {
            refundAmount = event_.ticketPrice;
        }

        (bool success, ) = payable(ticket.attendee).call{value: refundAmount}("");
        require(success, "Refund failed");
    }

    /**
     * @dev Update event status
     */
    function updateEventStatus(uint256 _eventId) 
        external 
    {
        Event storage event_ = events[_eventId];
        
        if (block.timestamp >= event_.startTime && block.timestamp < event_.endTime) {
            event_.status = EventStatus.Ongoing;
        } else if (block.timestamp >= event_.endTime) {
            event_.status = EventStatus.Completed;
        }
    }

    /**
     * @dev Get event details
     */
    function getEvent(uint256 _eventId) 
        external 
        view 
        returns (
            uint256 id,
            address organizer,
            string memory name,
            string memory location,
            uint256 startTime,
            uint256 endTime,
            uint256 attendeeCount,
            uint256 maxAttendees,
            EventStatus status
        )
    {
        Event memory event_ = events[_eventId];
        return (
            event_.id,
            event_.organizer,
            event_.name,
            event_.location,
            event_.startTime,
            event_.endTime,
            event_.attendeeCount,
            event_.maxAttendees,
            event_.status
        );
    }

    /**
     * @dev Get event messages
     */
    function getEventMessages(uint256 _eventId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return eventMessageList[_eventId];
    }

    /**
     * @dev Get event tickets
     */
    function getEventTickets(uint256 _eventId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return eventTickets[_eventId];
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
