// SPDX-License-Identifier: WTFPL
pragma solidity ^0.8.0;

uint constant ONE_YEAR = 31536000;

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract NovaDAO {
    address public asset;
    uint256 public minimumProposerBalance;
    uint256 public nextPollId;
    uint256 public proposerLock;
    address public feesMaster;

    mapping(uint256 => address) private polls;

    constructor() {
        asset = 0x02C13f421ABCdD8A11faC1a4aE43c59d51FB9e19;
        minimumProposerBalance = 10000 * 10 ** 18;
        proposerLock = 100 * 10 ** 18;
        feesMaster = msg.sender;
    }

    function getPollAddress(uint256 _pollId) public view returns(address) {
        return polls[_pollId];
    }

    function isPollPassed(uint256 _pollId) public view returns(bool) {
        return NovaPoll(polls[_pollId]).isPassed();
    }

    function changeFees(uint256 _newMinBalance, uint256 _newLockAmount) public {
        require(msg.sender == feesMaster, "unauthorized");

        minimumProposerBalance = _newMinBalance;
        proposerLock           = _newLockAmount;
    }
    
    function createPoll(
        uint32 _duration,
        bytes32 _termsHash,
        uint256 _quorum
    ) public returns(address _newPoll) {
        IERC20 _asset = IERC20(asset);
        require(_asset.balanceOf(msg.sender) >= minimumProposerBalance, "not enough coins");

        _newPoll = address(new NovaPoll(_duration, _termsHash, _quorum));

        require(_asset.transferFrom(msg.sender, _newPoll, proposerLock));
        // refunded only in case of passed poll discouraging proposers to create junk polls

        polls[nextPollId] = _newPoll;
        nextPollId++;
    }
}

contract NovaPoll {
    address public parent;
    address public proposer;
    uint256 public proposerLock;
    uint256 public quorum;
    bytes32 public termsHash; // we move terms off chain to save on gas
    bool    public decisionTaken;
    bool    public isPassed;
    uint256 public decidedAfter;

    uint256 public forWeight;
    uint256 public againstWeight;

    mapping(address => uint256) public lockedCoins;

    constructor(
        uint32  _duration, 
        bytes32 _termsHash,
        uint256 _quorum 
    ) {
        require(_duration <= ONE_YEAR, "duration cannot exceed one year");
        // contract is locking coins 'till decision is taken. we won't lock'em 4 more than a year

        parent              = msg.sender;
        NovaDAO _context    = NovaDAO(parent);

        decidedAfter = block.timestamp + _duration;
        termsHash    = _termsHash;
        quorum       = _quorum;
        proposer     = tx.origin;
        proposerLock = _context.proposerLock();
    }

    function vote(bool _for, uint256 _power) public {
        require(block.timestamp < decidedAfter, "no votes accepted anymore");

        NovaDAO _context    = NovaDAO(parent);
        IERC20     _asset   = IERC20(_context.asset());
        require(_asset.transferFrom(msg.sender, address(this), _power), "asset lock failed");

        if (_for)
            forWeight           += _power;
        else
            againstWeight       += _power;

        lockedCoins[msg.sender] += _power;
    }

    function takeDecision() public {
        require(!decisionTaken && block.timestamp >= decidedAfter, "already decided or voting active");
        
        decisionTaken = true;
        isPassed      = forWeight + againstWeight >= quorum && forWeight > againstWeight;
    }

    function unlockCoins() public {
        if (!decisionTaken) takeDecision();

        uint256 _unlockAmount = lockedCoins[msg.sender];
        lockedCoins[msg.sender] = 0;

        if (msg.sender == proposer && isPassed)
            _unlockAmount += proposerLock;

        NovaDAO _context    = NovaDAO(parent);
        IERC20     _asset   = IERC20(_context.asset());
        _asset.transfer(msg.sender, _unlockAmount);
    }
}