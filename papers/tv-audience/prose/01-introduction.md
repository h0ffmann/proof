# Introduction {#sec:intro}

A broadcaster sells a big show before it airs. The price of an advertising break depends on a
forecast of its audience, and the forecast decides how the channel schedules the rest of the
night. The usual approach treats each channel as its own time series: last week's audience in the
same hour, the programme's genre, the calendar and a model on top.

That approach misses the competition. At 21h on a Sunday, the viewers who watch a football final
on one channel do not watch the drama on the next. When two channels put their strongest shows in
the same hour, both lose viewers to each other. A model that sees only its own channel cannot know
this. It can also predict that three channels together draw more viewers than the number of people
in front of a TV set.

This paper asks a narrow question. For big shows on the main free-to-air channels, does a model
that predicts all channels of a slot together beat strong single-channel models? We compare five
forecasters:

1. **XGBoost** [@chen2016xgboost], gradient-boosted trees on one row per channel and slot;
2. **a deep neural network (DNN)**, a multilayer perceptron on the same features;
3. **Mistral Timestral** [@mistral2026timestral], a pretrained time-series foundation model used
   zero-shot;
4. **the Joint Competitive Share (JCS) model**, which forecasts the pool of viewers in the hour and
   splits it between the channels with a discrete-choice model;
5. **a neurosymbolic JCS**, in which a neural network learns the utilities inside the same
   symbolic structure.

We did not call the fourth approach "game theory". The channels do play a scheduling game: each
one chooses what to air knowing that its rivals do the same. But the forecaster does not solve
that game. It takes the published line-ups as given and predicts how viewers split between them.
"Joint competitive share" names what the model does: one joint forecast for all competitors of a
slot, built from shares of a common pool.

Real minute-by-minute ratings are sold under licence, so we test the models on a simulated
benchmark ([@Sec:data]). Every number in [@Sec:results] comes from synthetic data. To move from
simulation to real channels, [@Sec:groundtruth] names nine channels whose ratings are published
and a protocol to score frozen forecasts against them. [@Sec:nixtla] shows how the open-source
Nixtla libraries would shorten that work.
