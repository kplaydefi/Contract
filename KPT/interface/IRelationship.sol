pragma solidity >=0.5.0 <0.7.0;

interface IRelationship {
    /**
    * return false if user already binded，else return true or bind to proxy then return true
    */
    function verifyAndBind(address user, address proxy) external returns (bool);

    /**
    * return true when user binded to proxy
    */
    function isBinded(address user, address proxy) external returns (bool);
    function isProxy(address proxy) external returns (bool);
}