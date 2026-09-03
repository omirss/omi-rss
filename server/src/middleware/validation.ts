import type { Request, Response, NextFunction, RequestHandler } from 'express';
import { validationResult } from 'express-validator';
import type { z } from 'zod';

export const validate = (req: Request, res: Response, next: NextFunction): void => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    res.status(400).json({
      success: false,
      error: 'Validation failed',
      errors: errors.array().map((e) => ({
        field: e.type === 'field' ? e.path : undefined,
        message: String(e.msg),
      })),
    });
    return;
  }
  next();
};

type RequestSchema = z.ZodType<{ body?: unknown; query?: unknown; params?: unknown }>;

export const validateRequest = (schema: RequestSchema): RequestHandler => {
  return (req, res, next) => {
    const input: { body?: unknown; query?: unknown; params?: unknown } = {
      body: req.body,
      query: req.query,
      params: req.params,
    };
    const result = schema.safeParse(input);

    if (!result.success) {
      res.status(400).json({
        error: 'Validation failed',
        errors: result.error.errors.map((e) => ({
          field: e.path.join('.'),
          message: e.message,
        })),
        timestamp: new Date().toISOString(),
      });
      return;
    }

    if (result.data.body !== undefined) req.body = result.data.body;
    if (result.data.query !== undefined) req.query = result.data.query as typeof req.query;
    if (result.data.params !== undefined) req.params = result.data.params as typeof req.params;
    next();
  };
};
