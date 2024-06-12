# Programmable network, second homework
This project creates a consensus system among multiple switches managed by kathara via the p4 language based on the following [topology](/shared/topology.png).  
Each switch will compile and run [consensus.p4](/shared/consensus.p4), located in /shared, to both manage the consensus algorithm and the IP forwarding. 

The technology supported by this projects are: 
- Ethernet
- IPv4
- IPv6
- TCP
- UDP

## Consensus header
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

In fact, we just need to check that there are more positive votes than the sum of the negative votes and the switch that didn't vote at all.

### Ingress processing
The consensus header is added once to every packet as soon as it is seen by any switch running the p4 program. The ingress processing apply adds the consensus header as soon as it sees any packet that hasn't consensus already installed.
```
apply {
  // Add the consensus header if it doesn't exists
  if(!hdr.consensus.isValid()) consensus_ingress();

  ...
}
```
Here is the link to the [consensus_ingress action](https://github.com/filwastaken/programmable_hw2/blob/main/shared/consensus.p4?plain=1#L188).

## IP forwarding
We have also implemented forwarding functions for IPv4 and IPv6. In case the switch processing the packet is the last one before the destination, the consensus header needs to be evaluted and removed before forwarding. In particular, we have defined four functions:
1. ipv4_forwarding
2. ipv6_forwarding
3. ipv4_lastHop
4. ipv6_lastHop

Where the first two recreate the simple IP forwarding and the last two evalute the consensus header and remove it before forwarding the packet:
```
action ipv4_forward(bit<9> port) {
    hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    standard_metadata.egress_spec = port;
}

action ipv4_lastHop(bit<9> port){
    // If meta.consensus is not positive, the packet must be dropped
    meta.consensus = hdr.consensus.allow - hdr.consensus.unallow;

    // Removing consensus header and forwarding packet
    hdr.ipv4.protocol = hdr.consensus.protocol;
    hdr.consensus.setInvalid();
    hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    standard_metadata.egress_spec = port;
}
```

This is the IPv4 code snippet, the full forwardings can be found at:
- [IPv4 forwarding](https://github.com/filwastaken/programmable_hw2/blob/main/shared/consensus.p4?plain=1#L201)
- [IPv4 last Hop](https://github.com/filwastaken/programmable_hw2/blob/main/shared/consensus.p4?plain=1#L211)
- [IPv6 forwarding](https://github.com/filwastaken/programmable_hw2/blob/main/shared/consensus.p4?plain=1#L206)
- [IPv6 last Hop](https://github.com/filwastaken/programmable_hw2/blob/main/shared/consensus.p4?plain=1#L222)

Since conditional processing is not allowed in the ingress actions, we have created a new metadata field that is set to be the difference between the number of switches which have allowed the packet and those which didn't. This value is then evaluted in the egress function in the following manner:

### Metadata definition
```
struct metadata {
    bit<8> consensus;
}
```

### Egress processing
```
apply {
    if(!hdr.consensus.isValid() && meta.consensus < 1 ){
        // Drop packet
        mark_to_drop(standard_metadata);
    }
}
```

As long as the consensus header has been set invalid from the lastHop function and the stored difference is non-positive, the packet must be dropped.

## Consensus actions

The possible actions of any consensus table for any switch are:
1. consent,
2. unconsent, used both to cast a negative vote and to abstain from voting.

In particular, we have defined when the switches will cast a positive or negative vote in each switch's table. When none apply, the default action unconsent will represent an abstained.

# Switches definitions
Since all the switches require the forwarding functionality, we have defined static routes in the commands.txt to allow every packet to its destination. However, since the switches only
check one layer to cast their vote, we have not defined any table rules for the layers that shouldn't be looked at by a particular switch. Moreover, we have set the function unconsent() as the
default for all the consensus tables, since there isn't any difference between not voting and voting negativly.

Here follows an high level explanation of every tables and actions defined for each switch, defined in each switch's comamnds.txt:
## S1 rules
### S1 consensus
The switch will consent:
1. Any IPv4 message from 00:00:00:00:10:00 to 00:00:00:00:20:00
2. Any IPv4 or IPv6 message from 00:00:00:00:20:00 to 00:00:00:00:40:00

The switch will not consent
1. Any IPv6 message from 00:00:00:00:10:00 to 00:00:00:00:20:00
2. Any IPv4 or IPv6 message from 00:00:00:00:10:00 to 00:00:00:00:30:00

### S1 routing
The forwarding rules are:
- Any packet towards 10.0.0.1 or 2001:db8:1234::1 needs to be forwarded through eth0 and will trigger ipvX_lastHop
- Any packet towards 10.0.0.2 or 2001:db8:1234::2 needs to be forwarded through eth1 and will trigger ipvX_lastHop
- Any packet towards 10.0.0.3 or 2001:db8:1234::3 needs to be forwarded through eth3 and will trigger ipvX_forward
- Any packet towards 10.0.0.4 or 2001:db8:1234::4 needs to be forwarded through eth2 and will trigger ipvX_forward

## S2 rules
### S2 consensus
The switch will consent:
1. Any IPv4 or IPv6 message from the host 1 (10.0.0.1 and 2001:db8:1234::1)
2. Any IPv4 message from the host 3 (10.0.0.3 and 2001:db8:1234::3)

The switch will not consent:
1. Any IPv4 message from the host 2 (10.0.0.2 and 2001:db8:1234::2)
2. Any IPv4 message from the host 4 (10.0.0.4 and 2001:db8:1234::4)

### S2 routing
The forwarding rules are:
- Any packet towards 10.0.0.1 or 2001:db8:1234::1 needs to be forwarded through eth0 and will trigger ipvX_forward
- Any packet towards 10.0.0.2 or 2001:db8:1234::2 needs to be forwarded through eth0 and will trigger ipvX_forward
- Any packet towards 10.0.0.3 or 2001:db8:1234::3 needs to be forwarded through eth2 and will trigger ipvX_forward
- Any packet towards 10.0.0.4 or 2001:db8:1234::4 needs to be forwarded through eth2 and will trigger ipvX_forward

## S3 rules
### S3 consensus
The switch will consent:
1. Any IPv4 or IPv6 message from host 1 (10.0.0.1 and 2001:db8:1234::1)
2. Any IPv6 message from host 3 (2001:db8:1234::3)
3. Any IPv4 or IPv6 message from host 4 (10.0.0.4 and 2001:db8:1234::4)

The switch will not consent:
1. Any IPv4 or IPv6 message from host 2 (10.0.0.2 or 2001:db8:1234::2)
2. Any IPv4 message from host 3 (10.0.0.3)

### S3 routing
The forwarding rules are:
- Any packet towards 10.0.0.1 or 2001:db8:1234::1 needs to be forwarded through eth0 and will trigger ipvX_forward
- Any packet towards 10.0.0.2 or 2001:db8:1234::2 needs to be forwarded through eth0 and will trigger ipvX_forward
- Any packet towards 10.0.0.3 or 2001:db8:1234::3 needs to be forwarded through eth2 and will trigger ipvX_forward
- Any packet towards 10.0.0.4 or 2001:db8:1234::4 needs to be forwarded through eth1 and will trigger ipvX_forward

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
- Any packet towards 10.0.0.1 or 2001:db8:1234::1 needs to be forwarded through eth1 and will trigger ipvX_forward
- Any packet towards 10.0.0.2 or 2001:db8:1234::2 needs to be forwarded through eth1 and will trigger ipvX_forward
- Any packet towards 10.0.0.3 or 2001:db8:1234::3 needs to be forwarded through eth0 and will trigger ipvX_lastHop
- Any packet towards 10.0.0.4 or 2001:db8:1234::4 needs to be forwarded through eth3 and will trigger ipvX_forward

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
- Any packet towards 10.0.0.1 or 2001:db8:1234::1 needs to be forwarded through eth1 and will trigger ipvX_forward
- Any packet towards 10.0.0.2 or 2001:db8:1234::2 needs to be forwarded through eth1 and will trigger ipvX_forward
- Any packet towards 10.0.0.3 or 2001:db8:1234::3 needs to be forwarded through eth0 and will trigger ipvX_forward
- Any packet towards 10.0.0.4 or 2001:db8:1234::4 needs to be forwarded through eth2 and will trigger ipvX_forward

## S6 rules
### S6 consensus
The switch will consent:
The switch will consent:
1. Any IPv4 message from 00:00:00:00:10:00 to 00:00:00:00:20:00
2. Any IPv4 or IPv6 message from 00:00:00:00:20:00 to 00:00:00:00:40:00

The switch will not consent
1. Any IPv6 message from  00:00:00:00:10:00 to 00:00:00:00:20:00
2. Any IPv4 or IPv6 message from 00:00:00:00:10:00 to 00:00:00:00:30:00

### S6 routing
The forwarding rules are:
- Any packet towards 10.0.0.1 needs to be forwarded through eth1 and will trigger ipvX_forward
- Any packet towards 2001:db8:1234::1 needs to be forwarded through eth0 and will trigger ipvX_forward
- Any packet towards 10.0.0.2 or 2001:db8:1234::2 needs to be forwarded through eth1 and will trigger ipvX_forward
- Any packet towards 10.0.0.3 or 2001:db8:1234::3 needs to be forwarded through eth0 and will trigger ipvX_forward
- Any packet towards 10.0.0.4 or 2001:db8:1234::4 needs to be forwarded through eth2 and will trigger ipvX_lastHop


Each switch configuration can be found at:
1. [s1 commands.txt](/s1/commands.txt)
2. [s2 commands.txt](/s2/commands.txt)
3. [s3 commands.txt](/s3/commands.txt)
4. [s4 commands.txt](/s4/commands.txt)
5. [s5 commands.txt](/s5/commands.txt)
6. [s6 commands.txt](/s6/commands.txt)
