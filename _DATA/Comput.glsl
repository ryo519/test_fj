﻿#version 430

//#extension GL_ARB_compute_variable_group_size : enable

//layout( local_size_variable ) in;
  layout( local_size_x = 10,
          local_size_y = 10,
          local_size_z =  1 ) in;

////////////////////////////////////////////////////////////////////////////////

  ivec3 _WorkGrupsN = ivec3( gl_NumWorkGroups );

//ivec3 _WorkItemsN = ivec3( gl_LocalGroupSizeARB );
  ivec3 _WorkItemsN = ivec3( gl_WorkGroupSize     );

  ivec3 _WorksN     = _WorkGrupsN * _WorkItemsN;

  ivec3 _WorkID     = ivec3( gl_GlobalInvocationID );

//############################################################################## ■

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【定数】

const float Pi  = 3.141592653589793;
const float Pi2 = Pi * 2.0;
const float P2i = Pi / 2.0;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【ルーチン】

float Pow2( in float X )
{
  return X * X;
}

//------------------------------------------------------------------------------

float length2( in vec3 V )
{
  return Pow2( V.x ) + Pow2( V.y ) + Pow2( V.z );
}

//------------------------------------------------------------------------------

vec2 VecToSky( in vec3 Vec )
{
  vec2 Result;

  Result.x = ( Pi - atan( -Vec.x, -Vec.z ) ) / Pi2;
  Result.y =        acos(  Vec.y           ) / Pi ;

  return Result;
}

//------------------------------------------------------------------------------

vec3 ToneMap( in vec3 Color, in float White )
{
  return clamp( Color * ( 1 + Color / White ) / ( 1 + Color ), 0, 1 );
}

//------------------------------------------------------------------------------

vec3 GammaCorrect( in vec3 Color, in float Gamma )
{
  vec3 Result;

  float G = 1 / Gamma;

  Result.r = pow( Color.r, G );
  Result.g = pow( Color.g, G );
  Result.b = pow( Color.b, G );

  return Result;
}

//------------------------------------------------------------------------------

float Fresnel( in vec3 Vec, in vec3 Nor, in float IOR )
{
  // float N = Pow2( IOR );
  // float C = dot( Vec, Nor );
  // float G = sqrt( N + Pow2( C ) - 1 );
  // float NC = N * C;
  // return ( Pow2( (  C + G ) / (  C - G ) )
  //        + Pow2( ( NC + G ) / ( NC - G ) ) ) / 2;

  float R = Pow2( ( IOR - 1 ) / ( IOR + 1 ) );
  float C = clamp( dot( Vec, Nor ), -1, 0 );
  return R + ( 1 - R ) * pow( 1 + C, 5 );
}

//------------------------------------------------------------------------------

uvec4 _RandSeed;

uint rotl( in uint x, in int k )
{
  return ( x << k ) | ( x >> ( 32 - k ) );
}

float Rand()
{
  const uint Result = rotl( _RandSeed[ 0 ] * 5, 7 ) * 9;

  const uint t = _RandSeed[ 1 ] << 9;

  _RandSeed[ 2 ] ^= _RandSeed[ 0 ];
  _RandSeed[ 3 ] ^= _RandSeed[ 1 ];
  _RandSeed[ 1 ] ^= _RandSeed[ 2 ];
  _RandSeed[ 0 ] ^= _RandSeed[ 3 ];

  _RandSeed[ 2 ] ^= t;

  _RandSeed[ 3 ] = rotl( _RandSeed[ 3 ], 11 );

  return float( Result ) / 4294967296.0;
}

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【外部変数】

layout( rgba32ui ) uniform uimage2D _Seeder;

writeonly uniform image2D _Imager;

layout( std430 ) buffer TCamera
{
  layout( row_major ) mat4 _Camera;
};

uniform sampler2D _Textur;

//############################################################################## ■

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TRay

struct TRay
{
  vec4 Pos;
  vec4 Vec;
  vec3 Wei;
  vec3 Emi;
};

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% THit

struct THit
{
  float t;
  int   Mat;
  vec4  Pos;
  vec4  Nor;
};

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【内部変数】

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【物体】

void ObjPlane( in TRay Ray, inout THit Hit )
{
  float t;

  if ( Ray.Vec.y < 0 )
  {
    t = ( Ray.Pos.y - -1.001 ) / -Ray.Vec.y;

    if ( ( 0 < t ) && ( t < Hit.t ) )
    {
      Hit.t   = t;
      Hit.Pos = Ray.Pos + t * Ray.Vec;
      Hit.Nor = vec4( 0, 1, 0, 0 );
      Hit.Mat = 1;
    }
  }
}

//------------------------------------------------------------------------------

void ObjSpher( in TRay Ray, inout THit Hit )
{
  float B, C, D, t;

  B = dot( Ray.Pos.xyz, Ray.Vec.xyz );
  C = length2( Ray.Pos.xyz ) - 1;

  D = Pow2( B ) - C;

  if ( D > 0 )
  {
    t = -B - sign( C ) * sqrt( D );

    if ( ( 0 < t ) && ( t < Hit.t ) )
    {
      Hit.t   = t;
      Hit.Pos = Ray.Pos + t * Ray.Vec;
      Hit.Nor = Hit.Pos;
      Hit.Mat = 3;
    }
  }
}

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【材質】

float _EmitShift = 0.0001;

////////////////////////////////////////////////////////////////////////////////

TRay MatSkyer( in TRay Ray, in THit Hit )
{
  TRay Result;

  Result.Vec = Ray.Vec;
  Result.Pos = Ray.Pos;
  Result.Wei = Ray.Wei;
  Result.Emi = Ray.Emi + texture( _Textur, VecToSky( Ray.Vec.xyz ) ).rgb;

  return Result;
}

//------------------------------------------------------------------------------

TRay MatMirro( in TRay Ray, in THit Hit )
{
  TRay Result;

  Result.Vec = vec4( reflect( Ray.Vec.xyz, Hit.Nor.xyz ), 0 );
  Result.Pos = Hit.Pos + _EmitShift * Hit.Nor;
  Result.Wei = Ray.Wei;
  Result.Emi = Ray.Emi;

  return Result;
}

//------------------------------------------------------------------------------

TRay MatWater( inout TRay Ray, in THit Hit )
{
  TRay Result;
  float IOR, F;
  vec4  Nor;

  if( dot( Ray.Vec.xyz, Hit.Nor.xyz ) < 0 )
  {
    IOR = 1.333 / 1.000;
    Nor = +Hit.Nor;
  }
  else
  {
    IOR = 1.000 / 1.333;
    Nor = -Hit.Nor;
  }

  F = Fresnel( Ray.Vec.xyz, Nor.xyz, IOR );

  if ( Rand() < F )
  {
    Result.Vec = vec4( reflect( Ray.Vec.xyz, Nor.xyz ), 0 );
    Result.Pos = Hit.Pos + _EmitShift * Nor;
    Result.Wei = Ray.Wei;
    Result.Emi = Ray.Emi;
  } else {
    Result.Vec = vec4( refract( Ray.Vec.xyz, Nor.xyz, 1 / IOR ), 0 );
    Result.Pos = Hit.Pos - _EmitShift * Nor;
    Result.Wei = Ray.Wei;
    Result.Emi = Ray.Emi;
  }

  return Result;
}

//------------------------------------------------------------------------------

vec3 waveLengthToRGB( in float lambda )
{
    //中心波長[nm]
    float r0 = 700.0; //赤色
    float g0 = 546.1; //緑色
    float b0 = 435.8; //青色
    float o0 = 605.0; //橙色
    float y0 = 580.0; //黄色
    float c0 = 490.0; //藍色
    float p0 = 400.0; //紫色

    //半値半幅
    float wR = 90;
    float wG = 80;
    float wB = 80;
    float wO = 60;
    float wY = 50;
    float wC = 50;
    float wP = 40;
    //強度
    float iR = 0.95;
    float iG = 0.74;
    float iB = 0.75;

    float iO = 0.4;
    float iY = 0.1;
    float iC = 0.3;
    float iP = 0.3;

    //正規分布の計算
    float r = iR * exp( - ( lambda - r0 ) * ( lambda - r0 ) / ( wR * wR )  );
    float g = iG * exp( - ( lambda - g0 ) * ( lambda - g0 ) / ( wG * wG )  );
    float b = iB * exp( - ( lambda - b0 ) * ( lambda - b0 ) / ( wB * wB )  );
    float o = iO * exp( - ( lambda - o0 ) * ( lambda - o0 ) / ( wO * wO )  );
    float y = iY * exp( - ( lambda - y0 ) * ( lambda - y0 ) / ( wY * wY )  );
    float c = iC * exp( - ( lambda - c0 ) * ( lambda - c0 ) / ( wC * wC )  );
    float p = iP * exp( - ( lambda - p0 ) * ( lambda - p0 ) / ( wP * wP )  );

    /*
    orange #ffa500  1: 0.715 : 0.230
    yellow #ffff00  1: 1     : 0
    cian   #00ff00  0: 1     : 1
    purple #804080  1: 0.5   : 1
    */

    r = r + o + y + p;
    g = g + o*0.715 + y*0.83 + c + p *0.50;
    b = b + o*0.23 + c + p;

    if( r > 1.0 ) r = 1.0;
    if( g > 1.0 ) g = 1.0;
    if( b > 1.0 ) b = 1.0;

    return vec3(r,g,b);
}

TRay MatThinf( in TRay Ray, in THit Hit )
{
  TRay Result;
  float IOR, D, m, C, lambda;                                              // Dとlambdaは、D nm、lambda nmとする

  IOR = 1.333;
  D = 1000;
  m = 0;

  C = sqrt( 1 - ( 1 - Pow2( dot( Hit.Nor, -Ray.Vec ) ) ) / Pow2( IOR ) );
  lambda = 2 * IOR * D * C / (m + 0.5);

  for( m = 0; lambda < 380 && lambda > 750 && lambda > 370; m += 1.0)             // lambdaが380~750に収まる予定で書いてるけど大丈夫なのか？
  {
    lambda = 2 * IOR * D * C / (m + 0.5);
  }


  Result.Vec = Ray.Vec;
  Result.Pos = Ray.Pos;
  Result.Wei = Ray.Wei;
  Result.Emi += waveLengthToRGB( lambda );


  return Result;
}


//##############################################################################

void Raytrace( inout TRay Ray )
{
  THit Hit;

  for ( int L = 1; L <= 5; L++ )
  {
    Hit = THit( 10000, 0, vec4( 0 ), vec4( 0 ) );

    ///// 物体

    ObjSpher( Ray, Hit );
    ObjPlane( Ray, Hit );

    ///// 材質

    switch( Hit.Mat )
    {
      case 0: Ray = MatSkyer( Ray, Hit ); return;
      case 1: Ray = MatMirro( Ray, Hit ); break;
      case 2: Ray = MatWater( Ray, Hit ); break;
      case 3: Ray = MatThinf( Ray, Hit ); return;
    }
  }
}

//------------------------------------------------------------------------------

void main()
{
  vec4 E, S;
  TRay R;
  vec3 A, C, P;

  _RandSeed = imageLoad( _Seeder, _WorkID.xy );

  A = vec3( 0 );

  for ( int N = 1; N <= 16; N++ )
  {
    E = vec4( 0, 0, 0, 1 );

    S.x = 4.0 * ( _WorkID.x + 0.5 ) / _WorksN.x - 2.0;
    S.y = 1.5 - 3.0 * ( _WorkID.y + 0.5 ) / _WorksN.y;
    S.z = -2;
    S.w = 1;

    R.Pos = _Camera * E;
    R.Vec = _Camera * normalize( S - E );
    R.Wei = vec3( 1 );
    R.Emi = vec3( 0 );

    Raytrace( R );

    C = R.Wei * R.Emi;

    A += ( C - A ) / N;
  }

  P = GammaCorrect( ToneMap( A, 10 ), 2.2 );

  imageStore( _Imager, _WorkID.xy, vec4( P, 1 ) );

  imageStore( _Seeder, _WorkID.xy, _RandSeed );
}

//############################################################################## ■
