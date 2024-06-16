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
To manage consensus a "3.5 layer" header is inserted (between IP and TCP/UDP). This header has a total size of 16 bits:
```p4
header consensus_t {
    bit<8> allow;
    bit<8> protocol;
}
```
As defined by the assignment, we need the majority vote to allow the packet to the destination. This means that we can group the number of switches that don't vote and those that vote negativly against those that vote positivly for a particular packet.

$`pos > \frac{total}{2} = 2*pos > total = 2*pos > pos + neg + abst = pos > neg + abst = pos - (neg + abst) > 0`$

In fact, we just need to check that there are more positive votes than the sum of the negative votes and the switch that didn't vote at all.

$`
allowed = pos - (neg + abst)
allowed > 0
`$

### Ingress processing
The consensus header is added once to every packet as soon as it is seen by any switch running the p4 program. The ingress processing apply adds the consensus header as soon as it sees any packet that hasn't consensus already installed.
```p4
apply {
    // Add the consensus header if it doesn't exists
    if(!hdr.consensus.isValid()){
        if(hdr.ipv4.isValid()) ipv4_ingress();
        else ipv6_ingress();
    }

  ...
}
```
Here are the links to the two consensus ingress functions:
* [ipv4 ingress](https://github.com/filwastaken/programmable_hw2/blob/main/shared/consensus.p4?plain=1#L191)
* [ipv6_ingress](https://github.com/filwastaken/programmable_hw2/blob/main/shared/consensus.p4?plain=1#L197)


## IP forwarding
We have also implemented the forwarding functions for IPv4 and IPv6. In case the switch processing the packet is the last one before the destination, the consensus header needs to be evaluted and removed before forwarding. In particular, we have defined four functions:
1. ipv4_forwarding
2. ipv6_forwarding
3. ipv4_lastHop
4. ipv6_lastHop

Where the first two recreate the simple IP forwarding and the last two evalute the consensus header and remove it before forwarding the packet:
```p4
action ipv4_forward(bit<9> port) {
    hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    standard_metadata.egress_spec = port;
}

action ipv4_lastHop(bit<9> port){
    // If meta.consensus is not positive, the packet must be dropped
    meta.consensus = (hdr.consensus.allow > 0) ? 1w1 : 1w0;

    // Removing consensus header and forwarding packet
    hdr.ipv4.protocol = hdr.consensus.protocol;
    hdr.consensus.setInvalid();
    hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    standard_metadata.egress_spec = port;
}
```

This is the IPv4 code snippet, the full forwardings can be found at:
- [IPv4 forwarding](https://github.com/filwastaken/programmable_hw2/blob/main/shared/consensus.p4?plain=1#L204)
- [IPv4 last Hop](https://github.com/filwastaken/programmable_hw2/blob/main/shared/consensus.p4?plain=1#L214)
- [IPv6 forwarding](https://github.com/filwastaken/programmable_hw2/blob/main/shared/consensus.p4?plain=1#L209)
- [IPv6 last Hop](https://github.com/filwastaken/programmable_hw2/blob/main/shared/consensus.p4?plain=1#L225)

Since conditional processing is not allowed in the ingress actions, we have created a new metadata field that is set to be 1 if there are more switches that allowed the packet than those which didn't, 0 otherwise. This value is then used in the egress function to drop the packet in the following manner:

### Metadata definition
```p4
struct metadata {
    bit<1> consensus;
}
```

### Egress processing
```p4
apply {
    if(!hdr.consensus.isValid() && meta.consensus == 0){
        // Drop packet
        mark_to_drop(standard_metadata);
    }
}
```

As long as the consensus header has been set invalid from the lastHop function and the metadata field is 0, the packet will be dropped.

## Consensus actions

The possible actions of any consensus table for any switch are:
1. consent,
2. unconsent, used both to cast a negative vote and to abstain from voting.

In particular, we have defined when the switches will cast a positive or negative vote in each switch's table. When none apply, the default action unconsent will represent an abstained.

# Switches definitions
Since all the switches require the forwarding functionality, we have defined static routes in the commands.txt to allow every packet to its destination. However, since the switches only check one layer to cast their vote, we have not defined any table rules for the layers that shouldn't be looked at by a particular switch. Moreover, we have set the function unconsent() as the default for all the consensus tables, since there isn't any difference between not voting and voting negativly.

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
- Any packet towards 10.0.0.1 or 2001:db8:1234::1 will be forwarded through eth0 and will trigger ipvX_lastHop
- Any packet towards 10.0.0.2 or 2001:db8:1234::2 will be forwarded through eth1 and will trigger ipvX_lastHop
- Any packet towards 10.0.0.3 or 2001:db8:1234::3 will be forwarded through eth3 and will trigger ipvX_forward
- Any packet towards 10.0.0.4 or 2001:db8:1234::4 will be forwarded through eth2 and will trigger ipvX_forward

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
- Any packet towards 10.0.0.1 or 2001:db8:1234::1 will be forwarded through eth0 and will trigger ipvX_forward
- Any packet towards 10.0.0.2 or 2001:db8:1234::2 will be forwarded through eth0 and will trigger ipvX_forward
- Any packet towards 10.0.0.3 or 2001:db8:1234::3 will be forwarded through eth2 and will trigger ipvX_forward
- Any packet towards 10.0.0.4 or 2001:db8:1234::4 will be forwarded through eth2 and will trigger ipvX_forward

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
- Any packet towards 10.0.0.1 or 2001:db8:1234::1 will be forwarded through eth0 and will trigger ipvX_forward
- Any packet towards 10.0.0.2 or 2001:db8:1234::2 will be forwarded through eth0 and will trigger ipvX_forward
- Any packet towards 10.0.0.3 or 2001:db8:1234::3 will be forwarded through eth2 and will trigger ipvX_forward
- Any packet towards 10.0.0.4 or 2001:db8:1234::4 will be forwarded through eth1 and will trigger ipvX_forward

## S4 rules
### S4 consensus
The switch will consent:
1. Any UDP or TCP message with destination port 21
2. Any UDP or TCP message with destination port 22
3. Any UDP or TCP message with destination port 25
4. Any TCP message with destination port 80
5. Any UDP or TCP message with destination port 443
6. Any TCP message with destination port 445

The switch will not consent:
1. Any UDP or TCP message with destination port 69
2. Any UDP or TCP message with destination port 79
3. Any UDP message with destination port 80
4. Any UDP message with destination port 445

### S4 routing
The forwarding rules are:
- Any packet towards 10.0.0.1 or 2001:db8:1234::1 will be forwarded through eth1 and will trigger ipvX_forward
- Any packet towards 10.0.0.2 or 2001:db8:1234::2 will be forwarded through eth1 and will trigger ipvX_forward
- Any packet towards 10.0.0.3 or 2001:db8:1234::3 will be forwarded through eth0 and will trigger ipvX_lastHop
- Any packet towards 10.0.0.4 or 2001:db8:1234::4 will be forwarded through eth3 and will trigger ipvX_forward

## S5 rules
### S5 consensus
The switch will consent:
1. Any UDP or TCP message with destination port 22
2. Any TCP message with destination port 22
3. Any UDP or TCP message with destination port 25

The switch will not consent:
1. Any UDP or TCP message with destination port 21
2. Any UDP with destination port 22
3. Any UDP or TCP message with destination port 69
4. Any UDP or TCP message with destination port 79
5. Any UDP or TCP message with destination port 80
6. Any UDP or TCP message with destination port 443
7. Any UDP or TCP message with destination port 445

### S5 routing
The forwarding rules are:
- Any packet towards 10.0.0.1 or 2001:db8:1234::1 will be forwarded through eth1 and will trigger ipvX_forward
- Any packet towards 10.0.0.2 or 2001:db8:1234::2 will be forwarded through eth1 and will trigger ipvX_forward
- Any packet towards 10.0.0.3 or 2001:db8:1234::3 will be forwarded through eth0 and will trigger ipvX_forward
- Any packet towards 10.0.0.4 or 2001:db8:1234::4 will be forwarded through eth2 and will trigger ipvX_forward

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
- Any packet towards 10.0.0.1 will be forwarded through eth1 and will trigger ipvX_forward
- Any packet towards 2001:db8:1234::1 will be forwarded through eth0 and will trigger ipvX_forward
- Any packet towards 10.0.0.2 or 2001:db8:1234::2 will be forwarded through eth1 and will trigger ipvX_forward
- Any packet towards 10.0.0.3 or 2001:db8:1234::3 will be forwarded through eth0 and will trigger ipvX_forward
- Any packet towards 10.0.0.4 or 2001:db8:1234::4 will be forwarded through eth2 and will trigger ipvX_lastHop


Each switch configuration can be found at:
1. [s1 commands.txt](/s1/commands.txt)
2. [s2 commands.txt](/s2/commands.txt)
3. [s3 commands.txt](/s3/commands.txt)
4. [s4 commands.txt](/s4/commands.txt)
5. [s5 commands.txt](/s5/commands.txt)
6. [s6 commands.txt](/s6/commands.txt)
