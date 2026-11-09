% Expected: Theorem
% Function composition is associative, by extensionality: the order in which a pipeline's stages
% are grouped does not change the pipeline.
thf(compose, conjecture,
    ! [F: $i > $i, G: $i > $i, H: $i > $i] :
      ((^ [X: $i] : (F @ ((^ [Y: $i] : (G @ (H @ Y))) @ X)))
     = (^ [X: $i] : ((^ [Y: $i] : (F @ (G @ Y))) @ (H @ X))))).
