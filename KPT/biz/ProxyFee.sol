pragma solidity >=0.5.0 <0.7.0;


import "../../library/SafeMath.sol";
import "../../access/WhitelistedRole.sol";
import "../common/MixinResolver.sol";


contract ProxyFee is MixinResolver, WhitelistedRole {
    using SafeMath for uint256;
    
    mapping(address => uint256) private _deposits;
    mapping(address => uint256) private _decuctions;
    uint256 private _totalDeposit;
    uint256 private _received;

    uint256 public gameFee = 2 * 10 ** 17;
    uint256 public bindFee = 1 * 10 ** 17;

    constructor() public {
    }

    function setGameFee(uint256 fee) public onlyOwner {
        gameFee = fee;
        emit SetGameFee(fee);
    }

    function setBindFee(uint256 fee) public onlyOwner {
        bindFee = fee;
        emit SetBindFee(fee);
    }

    function proxyRecharge(uint256 amount) public {
        require(relationship().isProxy(msg.sender), "ProxyFee: caller is not the proxy");
        require(amount > 0 , "ProxyFee: amount is zero");
        //授权校验?
        //require(kusd().allowance(msg.sender, address(this)) >= amount, "ProxyFee: allowance not enough");

        kusd().transferFrom(msg.sender, address(this), amount);
        _deposits[msg.sender] = _deposits[msg.sender] + amount;
        _totalDeposit = _totalDeposit + amount;

        emit ProxyRecharge(msg.sender, amount);
    }

    function rechargeTo(address proxy, uint256 amount) public onlyOwner {
        require(relationship().isProxy(proxy), "ProxyFee: caller is not the proxy");
        require(amount > 0 , "ProxyFee: amount is zero");
        //授权校验?
        //require(kusd().allowance(msg.sender, address(this)) >= amount, "ProxyFee: allowance not enough");

        kusd().transferFrom(msg.sender, address(this), amount);
        _deposits[proxy] = _deposits[proxy] + amount;
         _totalDeposit = _totalDeposit + amount;

        emit ProxyRecharge(proxy, amount);
    }

    function payNewGame(address proxy) public onlyWhitelisted {
        require(relationship().isProxy(msg.sender), "ProxyFee: caller is not the proxy");
        require(_deposits[proxy] >= gameFee, "ProxyFee: proxy deposit not enough, need to recharge");
        _deposits[proxy] = _deposits[proxy] - gameFee;
        _decuctions[proxy] = _decuctions[proxy] + gameFee;
        _received = _received + gameFee;

        emit ProxyPayNewGame(proxy, gameFee);
    }

    function payNewBind(address proxy) public onlyWhitelisted {
        require(relationship().isProxy(msg.sender), "ProxyFee: caller is not the proxy");
        require(_deposits[proxy] >= bindFee, "ProxyFee: proxy deposit not enough, need to recharge");
        _deposits[proxy] = _deposits[proxy] - bindFee;
        _decuctions[proxy] = _decuctions[proxy] + bindFee;
        _received = _received + bindFee;

        emit ProxyPayNewGame(proxy, bindFee);
    }

    function withdrawFee(address to, uint256 amount) public onlyOwner {
        require(to != address(0), "ProxyFee: to is zero address");
        uint256 actual = amount < _received ? amount : _received;
        kusd().transfer(to, actual);
    }

    event ProxyRecharge(address indexed proxy, uint256 indexed amount);
    event SetGameFee(uint256 indexed fee);
    event SetBindFee(uint256 indexed fee);
    event ProxyPayNewGame(address indexed proxy, uint256 indexed fee);
    event ProxyPayNewBind(address indexed proxy, uint256 indexed fee);

}