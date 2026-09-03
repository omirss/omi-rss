import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import { logger } from '../utils/logger';

export class AppError extends Error {
  statusCode: number;
  isOperational: boolean;

  constructor(message: string, statusCode: number = 500, isOperational: boolean = true) {
    super(message);
    this.statusCode = statusCode;
    this.isOperational = isOperational;
    Error.captureStackTrace(this, this.constructor);
  }
}

export function errorHandler(err: Error, req: Request, res: Response, next: NextFunction) {
  let error = { ...err };
  error.message = err.message;

  // Log error
  logger.error({
    error: err,
    request: {
      method: req.method,
      url: req.url,
      ip: req.ip,
      userId: req.user?.id,
    },
  });

  // Zod validation error
  if (err instanceof ZodError) {
    const message = 'Validation failed';
    const errors = err.errors.map((e) => ({
      field: e.path.join('.'),
      message: e.message,
    }));
    return res.status(400).json({
      error: message,
      errors,
      timestamp: new Date().toISOString(),
    });
  }

  // JWT error
  if (err.name === 'JsonWebTokenError') {
    return res.status(401).json({
      error: 'Invalid token',
      timestamp: new Date().toISOString(),
    });
  }

  // Duplicate key error
  if (err.message?.includes('duplicate key')) {
    const field = err.message.match(/Key \((.*?)\)=/)?.[1] || 'field';
    return res.status(409).json({
      error: 'Duplicate value',
      field,
      timestamp: new Date().toISOString(),
    });
  }

  // App error
  if (err instanceof AppError) {
    return res.status(err.statusCode).json({
      error: err.message,
      timestamp: new Date().toISOString(),
    });
  }

  // Default error
  const statusCode = res.statusCode !== 200 ? res.statusCode : 500;
  res.status(statusCode).json({
    error: process.env.NODE_ENV === 'production' ? 'Internal server error' : err.message,
    ...(process.env.NODE_ENV !== 'production' && { stack: err.stack }),
    timestamp: new Date().toISOString(),
  });
}