pragma solidity >=0.5.0 <0.7.0;


import "../../library/SafeMath.sol";
import "../../library/Array.sol";
import "../../access/WhitelistedRole.sol";
import "../interface/IAggregator.sol";
import "../interface/IUniswap.sol";


contract ExchangeRates is WhitelistedRole {
    using SafeMath for uint256;
    using Array for bytes32[];

    uint private UNIT = 10 ** 18;

    bytes32 constant public KUSD = "KUSD";
    uint256 private _period = 60 days;
    uint256 private _future = 30 days;

    mapping(bytes32 => Feed) private _feeds;
    bytes32[] public feeds;

    mapping(bytes32 => IAggregator) private _aggregators;
    bytes32[] public aggregators;

    mapping(bytes32 => Trigger) private _triggers;
    bytes32[] public triggers;

    struct Feed {
        uint256 price;
        uint256 timestamp;
    }

    struct Trigger {
        uint256 price;
        uint256 upper;
        uint256 lower;
        bool frozen;
    }

    mapping(bytes32 => address) private _uniContracts;

    constructor() public {
        _setFeed(KUSD, SafeMath.wad(), now);
    }

    function period() public view returns (uint256) {
        return _period;
    }

    function uniAddr(bytes32 node) public view returns (address) {
        return _uniContracts[node];
    }

    function _setUniAddr(bytes32 node, address content) internal {
        _uniContracts[node] = content;
    }

    function setUniAddr(bytes32[] memory nodes, address[] memory contents) public onlyOwner {
        require(nodes.length == contents.length, "ExchangeRates: nodes and contents length mismatched");

        for (uint256 index = 0; index < nodes.length; index++) {
            _setUniAddr(nodes[index], contents[index]);
        }
    }

    function setPeriod(uint256 newPeriod) public onlyOwner {
        emit PeriodUpdated(_period, newPeriod);
        _period = newPeriod;
    }

    function future() public view returns (uint256) {
        return _future;
    }

    function setFuture(uint256 newFuture) public onlyOwner {
        emit FutureUpdated(_future, newFuture);
        _future = newFuture;
    }


    function getFeed(bytes32 currency) public view returns (uint256, uint256) {
        if (address(_aggregators[currency]) != address(0)) {
            return (uint256(_aggregators[currency].latestAnswer()), _aggregators[currency].latestTimestamp());
        } else {
            return (_feeds[currency].price, _feeds[currency].timestamp);
        }
    }

    function getFeedPrice(bytes32 currency) public view returns (uint256) {
        (uint256 price,) = getFeed(currency);
        return price;
    }

    function getFeedPrices(bytes32[] memory currencies) public view returns (uint256[] memory) {
        uint256[] memory prices = new uint256[](currencies.length);

        for (uint256 index = 0; index < currencies.length; index++) {
            prices[index] = getFeedPrice(currencies[index]);
        }

        return prices;
    }

    function getFeedPricesAndAnyExpired(bytes32[] memory currencies) public view returns (uint256[] memory, bool) {
        return (getFeedPrices(currencies), isAnyExpired(currencies));
    }

    function getFeedTimestamp(bytes32 currency) public view returns (uint256) {
        (,uint256 timestamp) = getFeed(currency);
        return timestamp;
    }

    function getFeedTimestamps(bytes32[] memory currencies) public view returns (uint256[] memory) {
        uint256[] memory timestamps = new uint256[](currencies.length);

        for (uint256 index = 0; index < currencies.length; index++) {
            timestamps[index] = getFeedTimestamp(currencies[index]);
        }

        return timestamps;
    }

    function _setFeed(bytes32 currency, uint256 price, uint256 timestamp) internal {
        Feed memory feed = Feed(price, timestamp);
        _feeds[currency] = feed;
    }

    function _setFeeds(bytes32[] memory currencies, uint256[] memory prices, uint256 timestamp) internal returns (bool) {
        require(currencies.length == prices.length, "ExchangeRates: curriencies and prices length mismatched");
        require(timestamp < (now + _future), "ExchangeRates: timestamp is exceeds future");

        for (uint256 index = 0; index < currencies.length; index++) {
            bytes32 currency = currencies[index];
            require(prices[index] != 0, "ExchangeRates: price can not be zero");
            require(currency != KUSD, "ExchangeRates: price of kusd can not be updated");

            if (timestamp < getFeedTimestamp(currency)) {
                continue;
            }
            prices[index] = getFeedOrTriggerPrice(currency, prices[index]);
            _setFeed(currency, prices[index], timestamp);
        }

        emit FeedsUpdated(currencies, prices, timestamp);

        return true;
    }

    function setFeeds(bytes32[] memory currencies, uint256[] memory prices, uint256 timestamp) public onlyWhitelisted returns (bool) {
        return _setFeeds(currencies, prices, timestamp);
    }

    function delFeed(bytes32 currency) public onlyWhitelisted {
        emit FeedDeleted(currency, getFeedPrice(currency), now);
        delete _feeds[currency];
    }

    function getFeedOrTriggerPrice(bytes32 currency, uint256 price) internal returns (uint256) {
        Trigger storage trigger = _triggers[currency];
        if (trigger.price <= 0) {
            return price;
        }

        uint256 feedOrTriggerPrice = getFeedPrice(currency);
        if (!trigger.frozen) {
            uint256 double = trigger.price.mul(2);
            if (double <= price) {
                feedOrTriggerPrice = 0;
            } else {
                feedOrTriggerPrice = double.sub(price);
            }

            if (feedOrTriggerPrice >= trigger.upper) {
                feedOrTriggerPrice = trigger.upper;
            } else if (feedOrTriggerPrice <= trigger.lower) {
                feedOrTriggerPrice = trigger.lower;
            }

            if (feedOrTriggerPrice == trigger.upper || feedOrTriggerPrice == trigger.lower) {
                trigger.frozen = true;
                emit TriggerFrozen(currency, price, feedOrTriggerPrice);
            }
        }

        return feedOrTriggerPrice;
    }

    function _setTrigger(bytes32 currency, Trigger memory trigger) internal returns (bool) {
        require(trigger.price > 0, "ExchangeRates: price must be above 0");
        require(trigger.lower > 0, "ExchangeRates: lower must be above 0");
        require(trigger.lower < trigger.price, "ExchangeRates: lower must be below the price");
        require(trigger.upper > trigger.price, "ExchangeRates: upper must be above the price");
        require(trigger.upper < trigger.price.mul(2), "ExchangeRates: upper must be less than double price");

        if (_triggers[currency].price <= 0) {
            triggers.push(currency);
        }

        _triggers[currency].price = trigger.price;
        _triggers[currency].upper = trigger.upper;
        _triggers[currency].lower = trigger.lower;
        _triggers[currency].frozen = trigger.frozen;

        emit TriggerAdded(currency, trigger.price, trigger.upper, trigger.lower);

        if (trigger.frozen) {
            emit TriggerFrozen(currency, trigger.price, trigger.price);
        }

        return true;
    }

    function setTrigger(bytes32 currency, uint256 price, uint256 upper, uint256 lower, bool frozen) public onlyOwner returns (bool) {
        Trigger memory trigger = Trigger(price, upper, lower, frozen);
        return _setTrigger(currency, trigger);
    }

    function delTrigger(bytes32 currency) public onlyOwner returns (bool) {
        Trigger memory trigger = _triggers[currency];
        require(trigger.price > 0, "ExchangeRates: no inverted price exists");

        _triggers[currency].price = 0;
        _triggers[currency].upper = 0;
        _triggers[currency].lower = 0;
        _triggers[currency].frozen = false;

        if (triggers.remove(currency)) {
            emit TriggerDeleted(currency, trigger.price, trigger.upper, trigger.lower);
        }

        return true;
    }

    function setAggregator(bytes32 currency, IAggregator aggregator) public onlyOwner {
        require(aggregator.latestTimestamp() >= 0, "ExchangeRates: aggregator is invalid");

        if (address(_aggregators[currency]) == address(0)) {
            aggregators.push(currency);
        }
        _aggregators[currency] = aggregator;

        emit AggregatorAdded(currency, aggregator);
    }

    function delAggregator(bytes32 currency) public onlyOwner {
        IAggregator aggregator = _aggregators[currency];
        require(address(aggregator) != address(0), "ExchangeRates: no aggregator exists for currency");
        delete _aggregators[currency];

        if (aggregators.remove(currency)) {
            emit AggregatorDeleted(currency, aggregator);
        }
    }

    function ratio(bytes32 source, uint256 amount, bytes32 destination) public view whenNotExpired(source) whenNotExpired(destination) returns (uint256) {
        if (source == destination) {
            return amount;
        }
        return amount.wmulRound(getUniPrice(source)).wdivRound(getUniPrice(destination));
    }

    function getUniPrice(bytes32 currency) public view returns (uint256) {
        require(uniAddr(currency) != address(0), "ExchangeRates: currency illegal");
        (uint160 sqrtPriceX96,,,,,,) = IUniswap(uniAddr(currency)).slot0();
        uint256 price = （uint256(sqrtPriceX96) ** 2).wmulRound(UNIT).wdivRound(2 ** 192);
        return price;
    }

    function isExpired(bytes32 currency) public view returns (bool) {
        if (currency == KUSD) {
            return false;
        }

        return getFeedTimestamp(currency).add(_period) < now;
    }

    function isAnyExpired(bytes32[] memory currencies) public view returns (bool) {
        for (uint256 index = 0; index < currencies.length; index++) {
            if (isExpired(currencies[index])) {
                return true;
            }
        }

        return false;
    }

    function isFrozen(bytes32 currency) public view returns (bool) {
        return _triggers[currency].frozen;
    }


    modifier whenExpired(bytes32 currency) {
        require(isExpired(currency), "ExchangeRates: currency timestamp is not expired");
        _;
    }

    modifier whenNotExpired(bytes32 currency) {
        require(!isExpired(currency), "ExchangeRates: currency timestamp is expired");
        _;
    }

    modifier frozen(bytes32 currency) {
        require(isFrozen(currency), "ExchangeRates: currency status is not frozen");
        _;
    }


    event PeriodUpdated(uint256 indexed previousPeriod, uint256 indexed newPeriod);
    event FutureUpdated(uint256 indexed previousFuture, uint256 indexed newFuture);
    event FeedsUpdated(bytes32[] currencies, uint256[] prices, uint256 timestamp);
    event FeedDeleted(bytes32 indexed currency, uint256  indexed price, uint256  indexed timestamp);
    event TriggerAdded(bytes32 indexed currency, uint256 indexed price, uint256 upper, uint256 lower);
    event TriggerDeleted(bytes32 indexed currency, uint256 indexed price, uint256 upper, uint256 lower);
    event TriggerFrozen(bytes32 indexed currency, uint256 indexed price, uint256 indexed feedOrTriggerPrice);
    event AggregatorAdded(bytes32 indexed currency, IAggregator indexed aggregator);
    event AggregatorDeleted(bytes32 indexed currency, IAggregator indexed aggregator);
}