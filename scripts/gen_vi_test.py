"""Reference optima for the variational-inference checks in math_mcmc (L060, D2841).

The mean-field Gaussian q = N(mean, diag(sd^2)) that maximises the ELBO of an
unnormalised log density f is deterministic; this script finds it by optimising the
ELBO with Gauss-Hermite quadrature for E_q[f] (scipy L-BFGS), independent of any
stochastic gradient, and prints the numbers the fixture embeds. Targets:

  A  bivariate normal, correlation 0.8: optimum sd = sqrt(1 - rho^2) (Bishop 10.1.2),
     ELBO closed form, checked against the quadrature optimum.
  B  a banana: f = -x^2/2 - (y - 0.5 x^2)^2 / (2 * 0.3^2).
  C  a log-gamma: f(z) = 3 z - exp(z)  (z = log x, x ~ Gamma(3, 1)); log Z = log Gamma(3).

    python scripts/gen_vi_test.py
"""
import math
import numpy as np
from scipy.optimize import minimize
from scipy.special import gammaln

NODES, WEIGHTS = np.polynomial.hermite_e.hermegauss(80)  # weight exp(-x^2/2)
WEIGHTS = WEIGHTS / math.sqrt(2.0 * math.pi)


def optimum(f, start):
    n = len(start) // 2
    grids = np.meshgrid(*([NODES] * n), indexing="ij")
    w = np.ones_like(grids[0])
    for axis in range(n):
        shape = [1] * n
        shape[axis] = len(NODES)
        w = w * WEIGHTS.reshape(shape)

    def negative_elbo(p):
        mean, log_sd = p[:n], p[n:]
        pts = [mean[i] + math.exp(log_sd[i]) * grids[i] for i in range(n)]
        expect = float((w * f(*pts)).sum())
        return -(expect + log_sd.sum() + 0.5 * n * (1.0 + math.log(2.0 * math.pi)))

    res = minimize(negative_elbo, np.array(start, float), method="BFGS", options={"gtol": 1e-10})
    return res.x[:n], np.exp(res.x[n:]), -res.fun


rho = 0.8
fa = lambda x, y: -(x * x - 2 * rho * x * y + y * y) / (2 * (1 - rho * rho))
mean, sd, bound = optimum(fa, [0.5, -0.5, 0.0, 0.0])
lam = 1.0 / (1 - rho * rho)
closed = -0.5 * (2 * lam * (1 - rho * rho)) + 2 * math.log(math.sqrt(1 - rho * rho)) + (1 + math.log(2 * math.pi))
log_z = math.log(2 * math.pi) + 0.5 * math.log(1 - rho * rho)
print("A mean", mean, "sd", sd, "elbo", bound, "closed", closed, "logZ", log_z)

fb = lambda x, y: -x * x / 2 - (y - 0.5 * x * x) ** 2 / (2 * 0.3 ** 2)
mean, sd, bound = optimum(fb, [0.2, 0.3, -0.5, -0.5])
print("B mean", mean, "sd", sd, "elbo", bound)

fc = lambda z: 3.0 * z - np.exp(z)
mean, sd, bound = optimum(fc, [0.0, 0.0])
print("C mean", mean, "sd", sd, "elbo", bound, "logZ", gammaln(3.0))
