// SPDX-License-Identifier: WTFPL

// This contract is made to replace an existing one with hardcoded emission limit of 2M NVC.
// Without the limit, DAO voting will be more honest 'cause every mainnet coin can be involved in voting process.
// Migration mechanism ensures that each new token can be minted by burning 1 old one at any time.
// New tokens are minted and destroyed by treasury in exchange for Mainnet coins locking.
// This token is made to bring modern Web3 infrastructure into NovaCoin ecosystem.
// We added "Wrapped" to the token name to avoid confusions.

pragma solidity ^0.8.0;

contract ERC20 {
    mapping(address => uint) public balances;
    mapping(address => mapping(address => uint)) public allowance;
    uint public totalSupply;
    string public name = "Wrapped Novacoin";
    string public symbol = "wNVC";
    uint8 public decimals = 18;
    address public migratingFrom = 0xBF84720097de111A80f46f9D077643967042841A;
    address public treasury = 0xB1C2F7Abb355151BAdF47655390dD259Ddf1bf3d;
    
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
    
    constructor() {
        emit Transfer(address(0), msg.sender, 0);
    }

    modifier reserved() {
        require(msg.sender == treasury, "not allowed");
        _;
    }

    function _mint(address to, uint value) private {
        totalSupply += value;
        balances[to] += value;

        emit Transfer(address(0), to, value);
    }
    
    function balanceOf(address owner) public view returns(uint) {
        return balances[owner];
    }
    
    function transfer(address to, uint value) public returns(bool) {
        require(balanceOf(msg.sender) >= value, "balance too low");
        balances[to] += value;
        balances[msg.sender] -= value;
        emit Transfer(msg.sender, to, value);
        return true;
    }
    
    function transferFrom(address from, address to, uint value) public returns(bool) {
        require(balanceOf(from) >= value, "balance too low");
        require(allowance[from][msg.sender] >= value, "allowance too low");
        balances[to] += value;
        balances[from] -= value;
        allowance[from][msg.sender] -= value; // allowance decrease
        emit Transfer(from, to, value);
        return true;   
    }
    
    function approve(address spender, uint value) public returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;   
    }

    // directly mints token instead of transferring them
    function mint(address to, uint value) public reserved {
        _mint(to, value);
    }

    function burn(uint value) public {
        require(balanceOf(msg.sender) >= value, "balance too low");

        totalSupply -= value;
        balances[msg.sender] -= value;

        emit Transfer(msg.sender, address(0), value);
    }

    function migrate() public {
        ERC20 _context = ERC20(migratingFrom);

        uint _migratingValue = _context.balanceOf(msg.sender);
        require(_context.transferFrom(msg.sender, address(0), _migratingValue), "burning failed");

        _mint(msg.sender, _migratingValue);
    }

    function changeMetadata(string memory _name, string memory _symbol) public reserved {
        name = _name;
        symbol = _symbol;
    }

    function assignTreasury(address _new) public reserved {
        treasury = _new;
    }
}
