# TV audience forecasting as a competition between channels

Forecasts of prime-time audiences, seven days ahead, for big shows on competing channels. Five
forecasters: XGBoost, a multilayer perceptron, Mistral's Timestral foundation model, the Joint
Competitive Share (JCS) model (slot viewing pool times multinomial-logit shares over all channels),
and a neurosymbolic JCS. A Nixtla HierarchicalForecast reconciliation is the coherence baseline.

The preprint [`papers/tv-audience`](../papers/tv-audience/metadata.md) has the full story. It is not peer reviewed. A built copy is [`papers/tv-audience/tv-audience.pdf`](../papers/tv-audience/tv-audience.pdf);
`just paper tv-audience` builds it.

**All data here are simulated.** `python/simulate.py` generates three markets (UK, US, BR) with
three placeholder channels each. No number in `results.md` describes a real channel. Section 6 of
the paper names nine real channels with public ratings and a protocol to test the models on them.

```bash
pip install numpy pandas scipy scikit-learn xgboost matplotlib hierarchicalforecast
python3 tv-audience/python/experiment.py   # writes results.md, results.json, figures/*.png
```

Mistral Timestral runs only when its package and weights are reachable:

```bash
pip install torch git+https://github.com/mistralai/timestral
python3 tv-audience/python/experiment.py   # downloads mistralai/Timestral-209M from Hugging Face
```

Without them the script prints `Timestral not run` and reports that arm as "not run".

The metrics, baselines and share layer are also defined in Agda, with their properties proved;
[`agda.md`](agda.md) says what is proved and what stays in the Python.

A Haskell pipeline runs the experiment as it is and computes its numbers again. They are every
score of every model, the JCS forecasts from the fitted weights, the gradient of the logit fit,
and the Agda theorems on the run's own numbers.
[`tools/tv-validate/`](../tools/tv-validate/README.md) says what it finds, among it which numbers
of `results.json` the pinned Nix shell gives back.

## Results (simulated test set, 1 Jan to 31 Oct 2026)

| Model | WAPE all | WAPE big shows | WAPE contested big shows |
|---|---|---|---|
| Seasonal naive | 19.0% | 55.1% | 52.8% |
| XGBoost | 15.5% | 21.7% | 25.0% |
| XGBoost + rival features | **15.1%** | 21.3% | 23.5% |
| DNN (MLP) | 20.7% | 27.6% | 25.8% |
| Mistral Timestral | not run | not run | not run |
| JCS | 16.2% | **20.1%** | **20.9%** |
| Neurosymbolic JCS | 15.9% | 22.5% | 24.1% |
| XGBoost + rivals + MinT (Nixtla) | 16.6% | 21.4% | 24.7% |

Full table with intervals: [`results.md`](results.md).
