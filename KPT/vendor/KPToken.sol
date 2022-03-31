pragma solidity >=0.5.0 <0.7.0;


import "../../erc20/ERC20.sol";
import "../../access/WhitelistedRole.sol";
import "../common/MixinResolver.sol";


contract KPToken is WhitelistedRole, ERC20, MixinResolver {
    
    constructor() ERC20("KPT", "KPT", 18) public {
        _mint(msg.sender, 2000000 * 1e18);
        addPauser(msg.sender);
        pause();
        addWhitelisted(msg.sender);
    }


    function mint(address _address, uint256 _amount) public onlyWhitelisted {
        require(_address != address(0), "KPToken: mint address is the zero address");
        _mint(_address, _amount);
        emit Mint(_address, _amount);
    }

    function unpausedApprove(address spender, uint256 amount) public onlyWhitelisted onlyNotBlacklisted(msg.sender) onlyNotBlacklisted(spender) returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function unpausedTransfer(address recipient, uint256 amount) public onlyWhitelisted onlyNotBlacklisted(msg.sender) onlyNotBlacklisted(recipient) returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function unpausedTransferFrom(address sender, address recipient, uint256 amount) public onlyWhitelisted onlyNotBlacklisted(msg.sender) onlyNotBlacklisted(sender) onlyNotBlacklisted(recipient) returns (bool) {
        uint256 delta = allowance(sender, msg.sender).sub(amount, "ERC20: decreased allowance below zero");
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, delta);
        return true;
    }


    event Mint(address indexed _address, uint256 indexed amount);
}
