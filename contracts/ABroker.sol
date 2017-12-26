pragma solidity ^0.4.18;

import "zeppelin-solidity/contracts/lifecycle/Destructible.sol";
import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "zeppelin-solidity/contracts/ECRecovery.sol";


contract ABroker is Destructible {
    using SafeMath for uint256;

    struct PaymentChannel {
        address sender;
        address receiver;
        uint256 value;

        uint32 settlingPeriod;
        uint256 settlingUntil;
    }

    mapping (bytes32 => PaymentChannel) public channels;

    uint32 public chainId;
    uint256 id;

    event DidOpen(bytes32 indexed channelId);
    event DidDeposit(bytes32 indexed channelId);
    event DidClaim(bytes32 indexed channelId);
    event DidStartSettling(bytes32 indexed channelId);
    event DidSettle(bytes32 indexed channelId);

    function ABroker(uint32 _chainId) public {
        chainId = _chainId;
        id = 0;
    }

    function open(address receiver, uint32 settlingPeriod) public payable {
        var channelId = keccak256(block.number + id++);
        channels[channelId] = PaymentChannel(
            msg.sender,
            receiver,
            msg.value,
            settlingPeriod,
            0
        );

        DidOpen(channelId);
    }

    function canDeposit(bytes32 channelId, address origin) public constant returns(bool) {
        var channel = channels[channelId];
        bool isSender = channel.sender == origin;
        return isOpen(channelId) && isSender;
    }

    function deposit(bytes32 channelId) public payable {
        require(canDeposit(channelId, msg.sender));

        channels[channelId].value += msg.value;

        DidDeposit(channelId);
    }

    function canStartSettling(bytes32 channelId, address origin) public constant returns(bool) {
        var channel = channels[channelId];
        bool isSender = channel.sender == origin;
        return isOpen(channelId) && isSender;
    }

    function startSettling(bytes32 channelId) public {
        require(canStartSettling(channelId, msg.sender));

        var channel = channels[channelId];
        channel.settlingUntil = block.number + channel.settlingPeriod;

        DidStartSettling(channelId);
    }

    function canSettle(bytes32 channelId, address origin) public constant returns(bool) {
        var channel = channels[channelId];
        bool isSender = channel.sender == origin;
        bool isWaitingOver = block.number >= channel.settlingUntil && isSettling(channelId);
        return isSender && isSettling(channelId) && isWaitingOver;
    }

    function settle(bytes32 channelId) public {
        require(canSettle(channelId, msg.sender));
        var channel = channels[channelId];
        require(channel.sender.send(channel.value));

        delete channels[channelId];
        DidSettle(channelId);
    }

    function canClaim(bytes32 channelId, uint256 payment, address origin, bytes signature) public constant returns(bool) {
        var channel = channels[channelId];
        bool isReceiver = origin == channel.receiver;
        var hash = signatureDigest(channelId, payment);
        bool isSigned = channel.sender == ECRecovery.recover(hash, signature);

        return isReceiver && isSigned;
    }

    function claim(bytes32 channelId, uint256 payment, bytes signature) public {
        require(canClaim(channelId, payment, msg.sender, signature));

        var channel = channels[channelId];

        if (payment > channel.value) {
            require(channel.receiver.send(channel.value));
        } else {
            require(channel.receiver.send(payment));
            require(channel.sender.send(channel.value.sub(payment)));
        }

        delete channels[channelId];

        DidClaim(channelId);
    }

    function isPresent(bytes32 channelId) public constant returns(bool) {
        var channel = channels[channelId];
        return channel.sender != 0;
    }

    function isSettling(bytes32 channelId) public constant returns(bool) {
        var channel = channels[channelId];
        return channel.settlingUntil != 0;
    }

    function isOpen(bytes32 channelId) public constant returns(bool) {
        return isPresent(channelId) && !isSettling(channelId);
    }

    function paymentDigest(bytes32 channelId, uint256 payment) public constant returns(bytes32) {
        return keccak256(address(this), chainId, channelId, payment);
    }

    function signatureDigest(bytes32 channelId, uint256 payment) public constant returns(bytes32) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        return keccak256(prefix, paymentDigest(channelId, payment));
    }
}
