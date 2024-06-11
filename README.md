# Programmable network, second homework
This project creates a consensus system among multiple switches managed by kathara via the p4 language [topology](/shared/hw2_layout.png).  
Each switch will compile and run [consensus.p4](/shared/consensus.p4), located in /shared, to both manage the consensus algorithm and the IP forwarding. 

The technology supported by this projects are: 
- Ethernet
- IPv4
- IPv6
- TCP
- UDP

To manage consensus a "3.5 layer" header is inserted (between IP and TCP/UDP). This header has a total size of 24 bits:
```
header consensus_t {
    bit<8> allow;
    bit<8> unallow;
    bit<8> protocol;
}
```
As defined by the assignment, we need the majority vote to allow the packet to the destination. This means that we can group the number of switches that don't vote and those that vote
negativly against those that vote positivly for a particular packet.

$`pos > \frac{total}{2} = 2*pos > total = 2*pos > pos + neg + abst = pos > neg + abst`$

The consensus header is added once to every packet as soon as it is seen by any switch running the p4 program
```
apply {
  // Add the consensus header if it doesn't exists
  if(!hdr.consensus.isValid()) consensus_ingress();

  ...
}
```
[consensus_ingress action](https://github.com/filwastaken/programmable_hw2/blob/9797e2387ffff7d6a58fd17dd72761d40da804bd/shared/consensus.p4?plain=1#L188).

This header is removed during the forwarding phase, in case the next hop is the destination host:

```
action ipv4_forward(bit<9> port, bit<1> lastSwitch) {
  if(lastSwitch){
    // Dropping packet in case it didn't pass the consensus!
    if(hdr.consensus.allow <= hdr.consensus.unallow) {
      mark_to_drop(standard_metadata);
      return ;
    }

    hdr.ipv4.protocol = hdr.consensus.protocol;
    hdr.consensus.setInvalid();
  }

  ...
```
This is the IPv4 code snippet, the full forwardings can be found at:
- [IPv4 forwarding](https://github.com/filwastaken/programmable_hw2/blob/9797e2387ffff7d6a58fd17dd72761d40da804bd/shared/consensus.p4?plain=1#L201)
- [IPv6 forwarding](https://github.com/filwastaken/programmable_hw2/blob/9797e2387ffff7d6a58fd17dd72761d40da804bd/shared/consensus.p4?plain=1#L217)

The possible actions for a switch are:
1. consent,
2. unconsent, used both to cast a negative vote and to abstain from voting.

In particular, we have defined when the switches will cast a positive or negative vote in each switch's table. When non apply, the default action unconsent will represent an abstained.

# Switches definitions
Since all the switches require the forwarding functionality, we have defined static routes in the commands.txt to allow every packet to its destination. However, since the switches only
check one layer to cast their vote, we have not defined any table rules for the layers that shouldn't be looked at by a particular switch. Moreover, we have set the function NoAction as the
default for all the consensus tables.

Here follows an high level explanation of every tables and actions defined for each switch, defined in each switch's comamnds.txt:
## S1 rules
### S1 consensus
The switch will consent:
1. Any IPv4 message from 00:00:00:00:10:00/36 to 00:00:00:00:20:00/36
2. Any IPv4 or IPv6 message from 00:00:00:00:20:00/36 to 00:00:00:00:40:00/36

The switch will not consent
1. Any IPv4 or IPv6 message from 00:00:00:00:10:00/36 to 00:00:00:00:30:00/36

### S1 routing
The forwarding rules are:
- Any packet towards 10.0.0.1 or 2001:db8:1234::1 needs to be forwarded through eth0 and the consensus header will be removed
- Any packet towards 10.0.0.2 or 2001:db8:1234::2 needs to be forwarded through eth1 and the consensus header will be removed
- Any packet towards 10.0.0.3 or 2001:db8:1234::3 needs to be forwarded through eth3 and the consensus header will be kept
- Any packet towards 10.0.0.4 or 2001:db8:1234::4 needs to be forwarded through eth2 and the consensus header will be kept

## S2 rules
### S2 consensus
The switch will consent:
1. Any IPv4 message from 10.0.0.1 to 10.0.0.3
2. Any IPv4 message from 10.0.0.2 to 10.0.0.3 and vice-versa (communication between host 2 and host 3 is allowed only for IP4)
3. Any IPv6 message from 2001:db8:1234::1 to 2001:db8:1234::3 and vice-versa (bidirectional communication between host 1 and host 3 is allowed only for IPv6)
4. Any IPv6 message from 2001:db8:1234::2 to 2001:db8:1234::4 and vice-versa (communication between host 2 and host 4 is allowed only for IPv6)

The switch will not consent:
1. Any IPv4 message from 10.0.0.3 to 10.0.0.1 (only one direction is allowed in IPv4)
2. Any IPv4 message from 10.0.0.1 to 10.0.0.4 and vice-versa
3. Any IPv4 message from 10.0.0.2 to 10.0.0.4 and vice-versa
4. Any IPv6 message from 2001:db8:1234::2 to 2001:db8:1234::3 and vice-versa

### S2 routing
The forwarding rules are:
- Any packet towards 10.0.0.1 or 2001:db8:1234::1 needs to be forwarded through eth0 and the consensus header will be kept
- Any packet towards 10.0.0.2 or 2001:db8:1234::2 needs to be forwarded through eth0 and the consensus header will be kept
- Any packet towards 10.0.0.3 or 2001:db8:1234::3 needs to be forwarded through eth2 and the consensus header will be kept
- Any packet towards 10.0.0.4 or 2001:db8:1234::4 needs to be forwarded through eth2 and the consensus header will be kept

## S3 rules
### S3 consensus
The switch will consent:
1. Any IPv4 message from 10.0.0.1 to 10.0.0.4 and vice-versa
2. Any IPv4 message from 10.0.0.2 to 10.0.0.4 and vice-versa
3. Any IPv6 message from 2001:db8:1234::2 to 2001:db8:1234::4 and vice-versa (bidirectional communication between host 2 and host 4 is allowed both in IPv4 and IPv6)
5. Any IPv6 message from 2001:db8:1234::1 to 2001:db8:1234::4

The switch will not consent:
1. Any IPv4 message from 10.0.0.2 to 10.0.0.3 and vice-versa
2. Any IPv6 message from 2001:db8:1234::3 to 2001:db8:1234::2 and vice-versa (communication between host 2 and 3 is not allowed either in IPv4 and IPv6)
3. Any IPv6 message from 2001:db8:1234::4 to 2001:db8:1234::1 (communication between host 1 and host 4 is allowed in one direction only in IPv6)

### S3 routing
The forwarding rules are:
- Any packet towards 10.0.0.1 or 2001:db8:1234::1 needs to be forwarded through eth0 and the consensus header will be kept
- Any packet towards 10.0.0.2 or 2001:db8:1234::2 needs to be forwarded through eth0 and the consensus header will be kept
- Any packet towards 10.0.0.3 or 2001:db8:1234::3 needs to be forwarded through eth2 and the consensus header will be kept
- Any packet towards 10.0.0.4 or 2001:db8:1234::4 needs to be forwarded through eth1 and the consensus header will be kept

## S4 rules
### S4 consensus
The switch will consent:
1. Any UDP message with source port 22
2. Any UDP message with source port 80
3. Any UDP message with source port 445
4. Any UDP message with destination port 22
5. Any UDP message with destination port 25
6. Any UDP message with destination port 445
7. Any TCP message with source port 80
8. Any TCP message with source port 445
9. Any TCP message with destination port 22
10. Any TCP message with destination port 445

The switch will not consent:
1. Any UDP message with source port 21
2. Any UDP message with source port 25
3. Any UDP message with destination port 21
4. Any UDP message with destination port 69
5. Any UDP message with destination port 79
6. Any TCP message with source port 21
7. Any TCP message with source port 22
8. Any TCP message with source port 25
9. Any TCP message with destination port 21
10. Any TCP message with destination port 25
11. Any TCP message with destination port 69
12. Any TCP message with destination port 79

### S4 routing
The forwarding rules are:
- Any packet towards 10.0.0.1 or 2001:db8:1234::1 needs to be forwarded through eth1 and the consensus header will be kept
- Any packet towards 10.0.0.2 or 2001:db8:1234::2 needs to be forwarded through eth1 and the consensus header will be kept
- Any packet towards 10.0.0.3 or 2001:db8:1234::3 needs to be forwarded through eth0 and the consensus header will be removed
- Any packet towards 10.0.0.4 or 2001:db8:1234::4 needs to be forwarded through eth3 and the consensus header will be kept

## S5 rules
### S5 consensus
The switch will consent:
1. Any UDP or TCP message with source port 21
2. Any UDP or TCP message with source port 22
3. Any UDP or TCP message with source port 80

The switch will not consent:
1. Any UDP or TCP message with destination port 21
2. Any UDP or TCP message with destination port 22
3. Any UDP or TCP message with destination port 25
4. Any UDP or TCP message with destination port 69
5. Any UDP or TCP message with destination port 79
6. Any UDP or TCP message with destination port 445

### S5 routing
The forwarding rules are:
- Any packet towards 10.0.0.1 or 2001:db8:1234::1 needs to be forwarded through eth1 and the consensus header will be kept
- Any packet towards 10.0.0.2 or 2001:db8:1234::2 needs to be forwarded through eth1 and the consensus header will be kept
- Any packet towards 10.0.0.3 or 2001:db8:1234::3 needs to be forwarded through eth0 and the consensus header will be kept
- Any packet towards 10.0.0.4 or 2001:db8:1234::4 needs to be forwarded through eth2 and the consensus header will be kept

## S6 rules
### S6 consensus
The switch will consent:
The switch will consent:
1. Any IPv4 message from 00:00:00:00:10:00/36 to 00:00:00:00:20:00/36
2. Any IPv4 or IPv6 message from 00:00:00:00:20:00/36 to 00:00:00:00:40:00/36

The switch will not consent
1.Any IPv6 message from  00:00:00:00:10:00/36 to 00:00:00:00:20:00/36
2. Any IPv4 or IPv6 message from 00:00:00:00:10:00/36 to 00:00:00:00:30:00/36

### S6 routing
The forwarding rules are:
- Any packet towards 10.0.0.1 needs to be forwarded through eth1 and the consensus header will be kept
- Any packet towards 2001:db8:1234::1 needs to be forwarded through eth0 and the consensus header will be kept
- Any packet towards 10.0.0.2 or 2001:db8:1234::2 needs to be forwarded through eth1 and the consensus header will be kept
- Any packet towards 10.0.0.3 or 2001:db8:1234::3 needs to be forwarded through eth0 and the consensus header will be kept
- Any packet towards 10.0.0.4 or 2001:db8:1234::4 needs to be forwarded through eth2 and the consensus header will be removed

# TODO:
1. Change permanent links to the updated p4 files to sync the new changes!
2. Finish testing the created env
3. Add a python program to test the consensus

