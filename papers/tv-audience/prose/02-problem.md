# The slot as a market {#sec:problem}

Take one market (a country), one day and one hour of prime time. We call this a *slot* $j$. In
the slot, $C$ channels each air one programme. Let $P_j$ be the number of people watching any TV
set in the hour: the *pool*. Panels measure it as total TV usage. Each viewer in the pool watches
one of the $C$ channels or something else: another channel, a streaming service or a game
console. We call that last group the *outside option*, with index 0.

The audience of channel $c$ is

$$A_{cj} = P_j \, s_{cj}, \qquad \sum_{c=1}^{C} s_{cj} \le 1 .$$ {#eq:split}

The shares $s_{cj}$ come from a multinomial logit, the standard model of choice between
differentiated products [@berry1994estimating]:

$$s_{cj} = \frac{\exp(u_{cj})}{1 + \sum_{k=1}^{C} \exp(u_{kj})}, \qquad u_{0j} = 0 .$$ {#eq:logit}

The utility $u_{cj}$ of a channel depends on its own programme and on its rivals' programmes.
Viewing choice models of this kind go back to the audience flow model of Rust and Alpert
[@rust1984audience], which also added *lead-in*: viewers tend to stay on the channel they
watched in the previous hour.

[@Eq:split] and [@eq:logit] encode three facts that a single-channel model must learn from data,
if it can learn them at all:

1. **Conservation.** Channel audiences cannot add up to more than the pool.
2. **Cannibalisation.** A stronger rival programme lowers every other channel's share.
3. **Market expansion.** A big show also raises $P_j$: people turn the TV on for a final.

A big show is where all three act at once. That is why we score the models separately on big
shows and on *contested* slots, where a big show meets another big show or a programme of the
same genre.
