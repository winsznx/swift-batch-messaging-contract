// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title CollaborativeStoryMessaging
 * @dev A contract for creating collaborative stories where users take turns adding segments
 * @author Swift v2 Team
 */
contract CollaborativeStoryMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event StoryStarted(
        uint256 indexed storyId,
        address indexed creator,
        string title,
        uint256 maxTurns
    );

    event SegmentAdded(
        uint256 indexed storyId,
        uint256 indexed segmentIndex,
        address indexed author,
        string content
    );

    event StoryCompleted(
        uint256 indexed storyId,
        uint256 timestamp
    );

    // Structs
    struct Segment {
        address author;
        string content;
        uint256 timestamp;
    }

    struct Story {
        uint256 id;
        address creator;
        string title;
        string prompt;
        uint256 maxTurns;
        uint256 currentTurn;
        bool isCompleted;
        uint256 createdAt;
        mapping(address => bool) isContributor; // Whitelist (optional)
        bool isPublic; // If false, only whitelist can contribute
    }

    // State variables
    Counters.Counter private _storyIdCounter;
    mapping(uint256 => Story) public stories;
    mapping(uint256 => Segment[]) public storySegments;
    
    uint256 public constant MAX_SEGMENT_LENGTH = 1000; // Characters

    constructor() {
        _storyIdCounter.increment();
    }

    /**
     * @dev Start a new collaborative story
     * @param _title Story title
     * @param _prompt Initial prompt or opening line
     * @param _maxTurns Maximum number of segments
     * @param _isPublic Whether anyone can contribute
     * @param _contributors Initial whitelist of contributors (if not public)
     */
    function startStory(
        string memory _title,
        string memory _prompt,
        uint256 _maxTurns,
        bool _isPublic,
        address[] memory _contributors
    ) external nonReentrant {
        require(bytes(_title).length > 0, "Title required");
        require(_maxTurns > 0, "Max turns must be positive");

        uint256 storyId = _storyIdCounter.current();
        _storyIdCounter.increment();

        Story storage story = stories[storyId];
        story.id = storyId;
        story.creator = msg.sender;
        story.title = _title;
        story.prompt = _prompt;
        story.maxTurns = _maxTurns;
        story.isPublic = _isPublic;
        story.createdAt = block.timestamp;

        if (!_isPublic) {
            story.isContributor[msg.sender] = true;
            for (uint256 i = 0; i < _contributors.length; i++) {
                story.isContributor[_contributors[i]] = true;
            }
        }

        emit StoryStarted(storyId, msg.sender, _title, _maxTurns);
    }

    /**
     * @dev Add a segment to the story
     * @param _storyId Story ID
     * @param _content Segment content
     */
    function addSegment(uint256 _storyId, string memory _content) external nonReentrant {
        Story storage story = stories[_storyId];
        require(story.id != 0, "Story does not exist");
        require(!story.isCompleted, "Story completed");
        require(story.currentTurn < story.maxTurns, "Max turns reached");
        require(bytes(_content).length > 0, "Content empty");
        require(bytes(_content).length <= MAX_SEGMENT_LENGTH, "Content too long");

        if (!story.isPublic) {
            require(story.isContributor[msg.sender], "Not a contributor");
        }

        // Prevent same user from posting twice in a row (optional rule, enabled here for better collaboration)
        if (story.currentTurn > 0) {
            Segment[] storage segments = storySegments[_storyId];
            require(segments[segments.length - 1].author != msg.sender, "Cannot post twice in a row");
        }

        Segment memory newSegment = Segment({
            author: msg.sender,
            content: _content,
            timestamp: block.timestamp
        });

        storySegments[_storyId].push(newSegment);
        story.currentTurn++;

        emit SegmentAdded(_storyId, story.currentTurn - 1, msg.sender, _content);

        if (story.currentTurn >= story.maxTurns) {
            story.isCompleted = true;
            emit StoryCompleted(_storyId, block.timestamp);
        }
    }

    /**
     * @dev Add contributor to whitelist (only creator)
     */
    function addContributor(uint256 _storyId, address _contributor) external {
        Story storage story = stories[_storyId];
        require(msg.sender == story.creator, "Only creator can add contributor");
        story.isContributor[_contributor] = true;
    }

    /**
     * @dev Get story details
     */
    function getStory(uint256 _storyId) external view returns (
        address creator,
        string memory title,
        string memory prompt,
        uint256 maxTurns,
        uint256 currentTurn,
        bool isCompleted,
        bool isPublic
    ) {
        Story storage story = stories[_storyId];
        return (
            story.creator,
            story.title,
            story.prompt,
            story.maxTurns,
            story.currentTurn,
            story.isCompleted,
            story.isPublic
        );
    }

    /**
     * @dev Get all segments of a story
     */
    function getStorySegments(uint256 _storyId) external view returns (Segment[] memory) {
        return storySegments[_storyId];
    }
}
