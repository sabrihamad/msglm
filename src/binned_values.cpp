#include "binned_values.h"

#include <algorithm>
#include <boost/accumulators/statistics/stats.hpp>
#include "logging.h"

BinnedValues::BinnedValues(const ImportedValues& values, double binWidth,
                           bool floor, double max_support_expand)
// define the bin bounds, avoid overexpanding the values support (in case of very distant outliers)
: val_min( std::max(values.val_min, 0.5*(values.support_min+values.support_max) - 0.5*max_support_expand*(values.support_max-values.support_min)) )
, val_max( std::min(values.val_max, 0.5*(values.support_min+values.support_max) + 0.5*max_support_expand*(values.support_max-values.support_min)) )
, step( binWidth )
, bins_sum( values.values.size() )
{
    if ( binWidth < 0 ) THROW_EXCEPTION( std::invalid_argument,
                                         "step=" << binWidth << " is negative " );
    if ( val_min == val_max ) {
        // degenerated case, everything concentrated at single value
        bins.resize( 1, 0 );
        bins[0] = bins_sum;
        return;
    }
    else {
        if ( binWidth == 0 ) THROW_EXCEPTION( std::invalid_argument,
                                              "step=" << binWidth );
        bins.resize( floor ? ( val_max - val_min ) / binWidth + 1
                     : std::ceil( ( val_max - val_min ) / binWidth ) + 1, 0 );
    }
    for ( std::size_t i = 0; i < values.values.size(); ++i ) {
        const double val = values.values[i];
        // quantize val and project it into [0, bins.size()-1] range
        int ix = std::min(std::max((int)(floor
               ? (val - val_min)/step
               : std::ceil((val_max - val)/step)), 0), (int)bins.size()-1);
#if 0
        if ( ix < 0 || ix >= bins.size() ) {
            THROW_EXCEPTION( Rcpp::exception,
                            "Bin index " << i << " for value " << val
                            << " out of bounds (" << bins.size() << "), "
                            << "[" << val_min << ", " << val_max << "]" );
        }
#endif
        bins[ix]++;
    }
#if 0
    std::size_t bins_sum_ = std::accumulate( bins.begin(), bins.end(), 0 );
    LOG_DEBUG2( "Sum is " << bins_sum_ );
    if ( bins_sum_ != bins_sum ) {
        THROW_EXCEPTION( Rcpp::exception,
                         bins_sum_ << " element(s) in bins, "
                         << bins_sum << " expected" );
    }
#endif
}

BinnedValues::BinnedValues(const bins_t& bins, double binWidth, double val_min, double val_max)
: val_min( val_min )
, val_max( val_max )
, step( binWidth )
, bins_sum( std::accumulate( bins.begin(), bins.end(), 0 ) )
, bins( bins )
{
}

// Probability that random variable
// would be less or equal than zero using the
// Gaussian kernel smoothing.
// @bins binned samples of random variable
// @start value corresponding to the first bin
// @step value step between the bins
// @bandwidth the Gaussian smoothing kernel bandwidth, defaults to the segment size, 0 disables smoothing
// @return P(X<=0) if negative, P(X>=0) if !negative
double BinnedValues::compareWithZero(double bandwidth, bool negative) const
{
    LOG_DEBUG2( "val_min=" << val_min << " val_max=" << val_max <<
                " step=" << step << " size=" << size() );
    if ( val_max == val_min ) {
        // distribution is degenerated
        LOG_DEBUG1( "Degenerated distribution" );
        LOG_DEBUG1( "val_min=" << val_min << " val_max=" << val_max );
        return ( R_IsNA( bandwidth )
                ? ( val_max <= 0 ? 1.0 : 0.0 )
                : R::pnorm( 0.0, val_max, bandwidth, negative, 0 ) );
    }
    else if ( (negative && ( ( val_max < -5.0*step*size() ) || ( val_min > 30.0*step*size() ) ))
           || (!negative && ( ( val_max < -30.0*step*size() ) || ( val_min > 5.0*step*size() ) ))
    ){
        // distribution is almost degenerated w.r.t. distance to zero
        // (30 times the value range)
        LOG_DEBUG1( "Almost degenerated distribution" );
        if ( R_IsNA( bandwidth ) ) {
            bandwidth = sqrt( norm_variance() );
        } else {
            bandwidth /= step;
        }
        LOG_DEBUG1( "Normalized bandwidth=" << bandwidth );
        return ( R::pnorm( 0.0, val_min / step + norm_average(), bandwidth, negative, 0 ) );
    }
    if ( bins_sum == 0 ) return ( 0.5 );

    // if bandwidth is not specified, use the rule-of-thumb
    if ( R_IsNA( bandwidth ) ) bandwidth = norm_bw_nrd();
    else {
        if ( bandwidth < 0 ) throw Rcpp::exception( "Negative bandwidth not allowed" );
        bandwidth /= step;
    }
    LOG_DEBUG2( "Normalized bandwidth=" << bandwidth );

    double res = 0.0;
    double offset = val_min / step + 0.5;
    if ( bandwidth > 0.0 ) {
        // integrate the Gaussian kernel probability across all bins
        for ( std::size_t i = 0; i < bins.size(); ++i ) {
            const size_t bin_i = bins[i];
            if (bin_i > 0) res += bin_i * R::pnorm( 0.0, offset + i, bandwidth, negative, 0 );
        }
    } else {
        // no kernel, count bins corresponding to non-positive differences
        for ( std::size_t i = std::max(0, (int)(-offset)-1); i < bins.size(); ++i ) {
            if ( offset + i <= 0.0 ) res += bins[i];
        }
        if ( !negative ) res = bins_sum - res;
    }
    LOG_DEBUG2((negative ? "P(X<=0)" : "P(X>=0)") << "=" << res / bins_sum);
    return res / bins_sum;
}

double BinnedValues::norm_average() const {
    if ( bins_sum > 0 ) {
        double res = 0.0;
        for ( std::size_t i = 0; i < bins.size(); ++i ) {
            res += bins[i] * i;
        }
        return res / bins_sum + 0.5;
    } else {
        return 0.0;
    }
}

double BinnedValues::norm_variance() const {
    if ( bins_sum > 0 ) {
        double res = 0.0;
        double avg = norm_average() - 0.5;
        for ( std::size_t i = 0; i < bins.size(); ++i ) {
            res += bins[i] * (i-avg) * (i-avg);
        }
        return res / bins_sum;
    } else {
        return 0.0;
    }
}

// rule-of-thumb method for bandwidth selection
// returns bw normalized by step, to get the bw, multiply it by step
// see R help: bw.nrd()
double BinnedValues::norm_bw_nrd(double bins_sum, double sd, double quartile1, double quartile3)
{
    double h = (quartile3 > quartile1 ? quartile3 - quartile1 : 1) / 1.34;
    double a = sd < h ? sd : h;
    LOG_DEBUG2( "q=(" << quartile1 << ", " << quartile3 << ") h=" << h << " sd=" << sd
                      << " res=" << a / pow(0.75 * bins_sum, 0.2));
    return a / pow(0.75 * bins_sum, 0.2);
}

// rule-of-thumb method for bandwidth selection
// returns bw normalized by step, to get the bw, multiply it by step
// see R help: bw.nrd()
double BinnedValues::norm_bw_nrd() const
{
    size_t i_quartile_1 = 0;
    size_t i_quartile_3 = 0;
    size_t n_elems = 0;
    for ( std::size_t i = 0; i < bins.size(); ++i ) {
        const size_t n_new_elems = n_elems + bins[i];
        if ( (4*n_elems < bins_sum) && (4*n_new_elems >= bins_sum) ) {
            i_quartile_1 = i;
        }
        if ( (4*n_elems < 3*bins_sum) && (4*n_new_elems >= 3*bins_sum) ) {
            i_quartile_3 = i;
            break;
        }
        n_elems = n_new_elems;
    }
    return norm_bw_nrd(bins_sum, sqrt(norm_variance()), i_quartile_1, i_quartile_3);
}

// make bins for the distribution of X-Y
BinnedValues BinnedValues::difference( const ImportedValues& xvals,
                                const ImportedValues& yvals,
                                std::size_t nsteps
){
    double step = ( ( xvals.val_max - xvals.val_min )
                    + ( yvals.val_max - yvals.val_min ) ) / nsteps;

    BinnedValues xbins( xvals, step, true );
    BinnedValues ybins( yvals, step, false );

    // use the bins of X and Y to calculate the distribution of X-Y
    bins_t diff( xbins.size() + ybins.size(), 0 );
    for ( std::size_t i = 0; i < xbins.size(); ++i ) {
        std::size_t x = xbins.bins[i];
        if ( x > 0 ) for ( std::size_t j = 0; j < ybins.size(); ++j ) {
            std::size_t y = ybins.bins[j];
            if ( y > 0 ) {
#if 0
                if ( i + j >= diff.size() ) {
                    THROW_EXCEPTION( Rcpp::exception,
                                     "Diff.Bin index " << i << "+" << j
                                    << "=" << (i+j)
                                    << " out of bounds (" << diff.size() << ")" );
                }
#endif
                diff[ i + j ] += x * y;
            }
        }
    }
    return ( BinnedValues( diff, step, xbins.val_min - ybins.val_max,
                           xbins.val_max - ybins.val_min ) );
}
