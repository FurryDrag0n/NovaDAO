pragma solidity ^0.8.0;

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

contract SmartVault {
    address public asset;
    address public rewardAsset;
    uint256 public rewardPool;

    uint256 public initDate;
    uint256 public finishDate;
    uint256 public unlockDate;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public scores;
    uint256 public globalScore;

    constructor(
        address _asset, 
        address _rewardAsset,
        uint256 _pool,

        uint24 _depositDuration,
        uint24 _stakeDuration
    ) {
        IERC20 _context = IERC20(_rewardAsset);

        require(
            _context.transferFrom(
                msg.sender, 
                address(this), 
                _pool
            ), 
            "reward locking failed"
        );
        rewardPool = _pool;
        rewardAsset = _rewardAsset;
        asset = _asset;

        initDate = block.timestamp;
        finishDate = initDate + _depositDuration;
        unlockDate = finishDate + _stakeDuration;
    }

    function lock(uint256 _amount) public {
        require(
            block.timestamp <= finishDate, 
            "staking period is over"
        );

        IERC20 _context = IERC20(asset);

        require(
            _context.transferFrom(
                msg.sender, 
                address(this), 
                _amount
            ), 
            "stake locking failed"
        );

        balances[msg.sender] += _amount;

        uint256 _score = (finishDate - block.timestamp) * _amount;
        scores[msg.sender] += _score;
        globalScore += _score;
    }

    function claim() public {
        require(
            block.timestamp >= unlockDate, 
            "staking is active"
        );

        IERC20 _context_A = IERC20(asset);
        IERC20 _context_B = IERC20(rewardAsset);

        uint256 _balance = balances[msg.sender];
        uint256 _reward = scores[msg.sender] * rewardPool / globalScore;

        balances[msg.sender] = 0;
        scores[msg.sender] = 0;

        require(
            _context_A.transfer(
                msg.sender,
                _balance
            ) &&
            _context_B.transfer(
                msg.sender,
                _reward
            ), 
            "stake unlocking failed"
        );
    }
}
