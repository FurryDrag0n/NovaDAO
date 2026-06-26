// SPDX-License-Identifier: WTFPL

pragma solidity ^0.8.0;

uint constant ONE_DAY = 60 * 60 * 24;
uint constant BOMB_DEADLINE = ONE_DAY * 7;
uint constant SWITCH_DEADLINE = ONE_DAY * 90;

uint constant MIN_PRICE_COINS = 10;
uint constant SWTCH_PULLING_REWARD_COINS = 1;

address constant COIN_CONTRACT = 0x55d398326f99059fF775485246999027B3197955; // USDT BEP20
address constant DAO_BUDGET = address(123); // to be defined

// @dev since we're using USDT BEP20, we're safe with this interface
// if you gonna use something else, consider upgrade to SafeERC20
interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// this contract uses Mutually Assured Destruction principle to guarantee safety for both counterparties
// making any attack unprofitable
contract MAD_escrow {
    // counterparties
    address public buyer;
    address public seller;
    address public DAO_budget; // instead of burning coins we can use them for constructive pruposes
    
    // asset and price info
    IERC20 public asset;
    uint public goodPrice;

    // status markers
    bool public isInit;
    bool public isCompleted;

    // proposal markers
    bool public finalityProposed;
    bool public proposedAsCompleted;
    address public proposer;

    // we leave a week 'till subject can destroy funds
    // this is sufficient to make eventual attacker change their mind
    uint public bombTimer;
    uint public switchTimer;
    uint public switchRewardWei;

    constructor(
        address _buyer,
        address _seller,
        uint _goodPrice
    ) {
        require(_buyer != _seller, "counterparties cannot have same address");
        buyer = _buyer;
        seller = _seller;
        asset = IERC20(COIN_CONTRACT); // USDT BEP20
        DAO_budget = DAO_BUDGET;

        uint _coinWei = 10 ** asset.decimals();
        uint _minPriceWei = MIN_PRICE_COINS * _coinWei;
        switchRewardWei = SWTCH_PULLING_REWARD_COINS * _coinWei;

        require(
            _goodPrice >= _minPriceWei && 
            switchRewardWei <= _minPriceWei / 10, 
            "price too low or switch reward too high"
        );
        
        goodPrice = _goodPrice;
    }

    // only subjects can enter
    modifier restricted() {
        require(msg.sender == buyer || msg.sender == seller, "not authorized");
        _;
    }

    // cannot call if contract is not yet initialized or already completed
    modifier active() {
        require(isActive(), "already completed");
        _;
    }

    // safe voting
    modifier vote() {
        require(proposer != msg.sender, "cannot self-vote");
        require(finalityProposed, "nothing to vote");
        _;
    }

    // shows if contract is active
    function isActive() public view returns(bool) {
        return isInit && !isCompleted;
    }

    // if timer is started subjects will be motivated in finding a consensus
    function isBombActive() public view returns(bool) {
        return bombTimer != 0;
    }
    
    // collateral locking function
    function lock() public {
        require(!isInit && !isCompleted, "already used");

        uint _buyerCollateral = goodPrice * 2; // when deal is completed, half of collateral returns to buyer
        uint _sellerCollateral = goodPrice;
        
        switchTimer = block.timestamp + SWITCH_DEADLINE;
        isInit = true;

        require(
            asset.transferFrom(
                buyer, 
                address(this), 
                _buyerCollateral
            ) &&
            asset.transferFrom(
                seller, 
                address(this), 
                _sellerCollateral
            ),
            "locking failed"
        );
    }

    // resolution proposal. it has binary completion status, passed or not
    function propose(bool _asCompleted) public active restricted {
        require(!finalityProposed, "already proposed");

        finalityProposed = true;
        proposedAsCompleted = _asCompleted;

        proposer = msg.sender;
    }

    // has built-in mechanism of refunding half of collateral to avoid subject disappearing after
    // receivement of good or service
    function approve() public vote active restricted {
        uint _buyerCollateral = goodPrice * (proposedAsCompleted ? 1 : 2);
        uint _sellerCollateral = goodPrice * (proposedAsCompleted ? 2 : 1);

        isCompleted = true;

        require(
            asset.transfer(buyer, _buyerCollateral) &&
            asset.transfer(seller, _sellerCollateral),
            "withdrawal failed"
        );
    }

    // we don't clear markers to not pay gas twice (we overwrite them in propose function)
    function reject() public vote active restricted {
        finalityProposed = false;
    }

    // nonsense destroy function to discourage eventual attacker. like atomic bomb
    // has built-in grace period to make subjects think twice
    function destroy() public active restricted {
        if (!isBombActive()) 
            bombTimer = block.timestamp + BOMB_DEADLINE;

        else if (bombTimer > block.timestamp)
            revert("canot destroy yet");

        else {
            isCompleted = true;

            require(
                asset.transfer(
                    DAO_budget, 
                    asset.balanceOf(address(this))
                ), 
                "transfer failed"
            );
        }
    }

    // Dead Man's Switch. can be called after deal completion deadline
    // caller is rewarded for attention and to cover gas fees
    function pullSwitch() public active {
        require(switchTimer <= block.timestamp, "cannot destroy yet");

        isCompleted = true;

        require(
            asset.transfer(
                DAO_budget, 
                asset.balanceOf(address(this)) - switchRewardWei
            ) &&
            asset.transfer(
                msg.sender,
                switchRewardWei
            ), 
            "transfer failed"
        );
    }
}